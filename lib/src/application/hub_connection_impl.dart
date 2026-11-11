import 'dart:async';
import 'dart:convert';

import '../core/logger.dart';
import '../data/mappers/message_mappers.dart';
import '../domain/entities/connection_info.dart';
import '../domain/entities/connection_state.dart';
import '../domain/entities/hub_invocation.dart';
import '../domain/entities/server_message.dart';
import '../domain/entities/transport_type.dart';
import '../domain/exceptions/signalr_exception.dart';
import '../domain/policies/reconnect_policy.dart';
import '../domain/repositories/client_transport.dart';
import '../domain/repositories/connection_session.dart';
import '../presentation/hub_connection.dart';
import '../presentation/hub_proxy.dart';
import 'connection_state_machine.dart';
import 'default_reconnect_policy.dart';
import 'hub_proxy_impl.dart';
import 'invocation_tracker.dart';
import 'keep_alive_monitor.dart';
import 'reconnect_service.dart';

/// Default [HubConnection].
class HubConnectionImpl implements HubConnection, HubInvoker {
  /// Creates a connection. Use `HubConnectionBuilder` instead.
  HubConnectionImpl({
    required ConnectionSessionFactory sessionFactory,
    TransportType transportType = TransportType.auto,
    ReconnectPolicy? reconnectPolicy,
    SignalRLogger logger = const NoopLogger(),
    Duration invocationTimeout = const Duration(seconds: 30),
  })  : _sessionFactory = sessionFactory,
        _transportType = transportType,
        _policy = reconnectPolicy,
        _logger = logger,
        _invocationTimeout = invocationTimeout;

  final ConnectionSessionFactory _sessionFactory;
  final TransportType _transportType;
  final ReconnectPolicy? _policy;
  final SignalRLogger _logger;
  final Duration _invocationTimeout;

  final _states = ConnectionStateMachine();
  final _tracker = InvocationTracker();
  final _proxies = <String, HubProxyImpl>{};

  final _slow = <void Function()>[];
  final _reconnecting = <void Function(Object?)>[];
  final _reconnected = <void Function(bool)>[];
  final _closed = <void Function(Object?)>[];

  int _run = 0;
  ConnectionSession? _session;
  ClientTransport? _transport;
  ConnectionInfo? _info;
  String? _messageId;
  String? _groupsToken;
  KeepAliveMonitor? _keepAlive;
  ReconnectService? _reconnect;
  DateTime _lastActive = DateTime.now();

  @override
  ConnectionState get state => _states.state;

  @override
  Stream<ConnectionState> get stateStream => _states.stream;

  @override
  TransportType? get transport =>
      state == ConnectionState.connected ? _transport?.type : null;

  @override
  String? get connectionId => _info?.connectionId;

  /// Number of invocations waiting for a result (for tests).
  int get pendingInvocations => _tracker.pendingCount;

  @override
  HubProxy createHubProxy(String hubName) {
    final key = hubName.toLowerCase();
    final existing = _proxies[key];
    if (existing != null) return existing;
    if (state != ConnectionState.disconnected) {
      throw StateError(
        'Hub proxies must be created before start() (hub: $hubName)',
      );
    }
    return _proxies[key] = HubProxyImpl(hubName, this, _logger);
  }

  @override
  void onConnectionSlow(void Function() callback) => _slow.add(callback);

  @override
  void onReconnecting(void Function(Object? error) callback) =>
      _reconnecting.add(callback);

  @override
  void onReconnected(void Function(bool newConnection) callback) =>
      _reconnected.add(callback);

  @override
  void onClosed(void Function(Object? error) callback) => _closed.add(callback);

  void _emit<T>(List<void Function(T)> list, T value) {
    for (final cb in List.of(list)) {
      try {
        cb(value);
      } catch (e) {
        _logger.log(LogLevel.error, 'Callback threw', e);
      }
    }
  }

  // ---------------------------------------------------------------- start

  @override
  Future<void> start() async {
    if (state != ConnectionState.disconnected) {
      throw StateError('start() called while $state');
    }
    final run = ++_run;
    _states.transition(ConnectionState.connecting);
    try {
      await _establish(run);
    } catch (e) {
      if (run == _run) {
        await _teardown(abort: true);
        _states.transition(ConnectionState.disconnected);
      }
      rethrow;
    }
    _onConnected();
  }

  void _checkRun(int run) {
    if (run != _run) {
      throw const SignalRException('Connection was stopped');
    }
  }

  Future<void> _establish(int run) async {
    await _teardown(abort: false);
    final session = _session = _sessionFactory.create([
      for (final p in _proxies.values) p.wireName,
    ]);
    final info = await session.negotiation.negotiate();
    _checkRun(run);
    _info = info;
    _messageId = null;
    _groupsToken = null;
    _logger.log(
      LogLevel.debug,
      'Negotiated ${info.connectionId} (tryWebSockets: ${info.tryWebSockets})',
    );
    if (!info.protocolVersion.startsWith('1.')) {
      throw NegotiateException(
        'Unsupported protocol ${info.protocolVersion}. '
        'Is this an ASP.NET Core SignalR server?',
      );
    }
    if (_transportType == TransportType.webSockets && !info.tryWebSockets) {
      throw const TransportException(
        'The server does not allow WebSockets (TryWebSockets: false)',
      );
    }
    final transport = _transport = session.createTransport(_transportType);
    var connecting = transport.connect(
      info,
      onMessage: (m) => _onMessage(run, m),
      onClose: (e) => _onTransportLost(run, e),
    );
    if (_transportType != TransportType.auto) {
      connecting = connecting.timeout(
        info.transportConnectTimeout,
        onTimeout: () => throw SignalRTimeoutException(
          '${_transportType.name} did not initialize in time',
        ),
      );
    }
    await connecting;
    _checkRun(run);
    await session.negotiation.start(transport.type, info);
    _checkRun(run);
  }

  void _onConnected() {
    _lastActive = DateTime.now();
    _states.transition(ConnectionState.connected);
    final timeout = _info?.keepAliveTimeout;
    _keepAlive?.stop();
    if (timeout != null && timeout > Duration.zero) {
      final run = _run;
      _keepAlive = KeepAliveMonitor(
        timeout: timeout,
        onSlow: () {
          _logger.log(LogLevel.warning, 'Connection is slow');
          for (final cb in List.of(_slow)) {
            cb();
          }
        },
        onTimeout: () => _onTransportLost(
          run,
          const SignalRTimeoutException('Keep-alive timed out'),
        ),
      )..start();
    }
    _logger.log(LogLevel.info, 'Connected (${_transport?.type.name})');
  }

  // ------------------------------------------------------------- messages

  void _onMessage(int run, ServerMessage message) {
    if (run != _run) return;
    _lastActive = DateTime.now();
    _keepAlive?.markActivity();
    switch (message) {
      case KeepAliveMessage():
        break;
      case InvocationResult():
        if (!message.isProgress) {
          _tracker.complete(message);
        }
      case PersistentResponse():
        if (message.messageId != null) _messageId = message.messageId;
        if (message.groupsToken != null) _groupsToken = message.groupsToken;
        for (final m in message.messages) {
          final proxy = _proxies[m.hub.toLowerCase()];
          if (proxy == null) {
            _logger.log(LogLevel.debug, 'Message for unknown hub ${m.hub}');
            continue;
          }
          proxy.dispatch(m);
        }
        if (message.disconnect) {
          _logger.log(LogLevel.info, 'Server asked to disconnect');
          scheduleMicrotask(() => _close(
                run,
                const SignalRException('Server requested disconnect'),
              ));
        } else if (message.shouldReconnect) {
          _onTransportLost(
              run, const SignalRException('Server asked to reconnect'));
        }
    }
  }

  // ------------------------------------------------------------ reconnect

  void _onTransportLost(int run, Object? error) {
    if (run != _run || state != ConnectionState.connected) return;
    unawaited(_reconnectLoop(run, error));
  }

  Future<void> _reconnectLoop(int run, Object? error) async {
    _logger.log(LogLevel.info, 'Transport lost, reconnecting', error);
    _keepAlive?.stop();
    _states.transition(ConnectionState.reconnecting);
    _tracker.failAll(
      SignalRException('Connection lost before the result was received',
          cause: error),
    );
    _emit(_reconnecting, error);
    await _transport?.close();
    final info = _info!;
    final window =
        info.disconnectTimeout + (info.keepAliveTimeout ?? Duration.zero);
    final service = _reconnect = ReconnectService(
      policy: _policy ?? ProtocolReconnectPolicy(window),
      window: window,
      allowRestart: _policy != null,
      logger: _logger,
      reconnectTransport: () async {
        final t = _transport!;
        try {
          await t
              .connect(
                info,
                onMessage: (m) => _onMessage(run, m),
                onClose: (e) => _onTransportLost(run, e),
                reconnect: ReconnectCursor(
                  messageId: _messageId,
                  groupsToken: _groupsToken,
                ),
              )
              .timeout(info.transportConnectTimeout);
        } catch (_) {
          await t.close();
          rethrow;
        }
      },
      restart: () => _establish(run),
    );
    final outcome = await service.run(lastActive: _lastActive, error: error);
    if (run != _run) return;
    _reconnect = null;
    switch (outcome) {
      case ReconnectOutcome.reconnected:
      case ReconnectOutcome.restarted:
        _onConnected();
        _emit(_reconnected, outcome == ReconnectOutcome.restarted);
      case ReconnectOutcome.gaveUp:
        await _close(run, service.lastError ?? error);
      case ReconnectOutcome.cancelled:
        break;
    }
  }

  // ------------------------------------------------------------ invoke

  @override
  Future<Object?> invokeHub(
    HubProxyImpl hub,
    String method,
    List<Object?> args,
    Duration? timeout,
  ) async {
    final transport = _transport;
    if (state != ConnectionState.connected || transport == null) {
      throw SignalRException(
        'Cannot invoke $method: connection is ${state.name}',
      );
    }
    final (id, future) = _tracker.register();
    final payload = jsonEncode(
      HubInvocation(
        hub: hub.wireName,
        method: method,
        args: args,
        id: id,
        state: hub.state.isEmpty ? null : Map.of(hub.state),
      ).toDto().toJson(),
    );
    _logger.log(LogLevel.trace, '-> $payload');
    try {
      await transport.send(payload);
    } catch (e) {
      _tracker.fail(id, e);
      future.ignore();
      if (e is SignalRException) rethrow;
      throw TransportException('Send failed', cause: e);
    }
    final InvocationResult result;
    try {
      result = await future.timeout(timeout ?? _invocationTimeout);
    } on TimeoutException {
      _tracker.remove(id);
      throw SignalRTimeoutException('No result for ${hub.hubName}.$method');
    }
    hub.updateState(result.state);
    if (result.hasError) {
      throw HubInvocationException(
        result.error!,
        errorData: result.errorData,
        isHubException: result.isHubException,
      );
    }
    return result.result;
  }

  // ------------------------------------------------------------- stop

  @override
  Future<void> stop() async {
    final wasActive = state != ConnectionState.disconnected;
    _run++;
    _reconnect?.cancel();
    _reconnect = null;
    await _teardown(abort: wasActive);
    if (_states.transition(ConnectionState.disconnected)) {
      _emit(_closed, null);
    }
  }

  Future<void> _close(int run, Object? error) async {
    if (run != _run) return;
    _run++;
    _reconnect?.cancel();
    _reconnect = null;
    await _teardown(abort: true);
    if (_states.transition(ConnectionState.disconnected)) {
      _emit(_closed, error);
    }
  }

  Future<void> _teardown({required bool abort}) async {
    _keepAlive?.stop();
    _keepAlive = null;
    _tracker.failAll(const SignalRException('Connection stopped'));
    final transport = _transport;
    final session = _session;
    final info = _info;
    _transport = null;
    _session = null;
    if (transport != null) {
      try {
        await transport.close();
      } catch (e) {
        _logger.log(LogLevel.debug, 'close failed', e);
      }
    }
    if (abort && session != null && info != null && transport != null) {
      final type = transport.type;
      if (type != TransportType.auto) {
        await session.negotiation.abort(type, info);
      }
    }
    session?.dispose();
  }
}
