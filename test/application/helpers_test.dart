import 'dart:async';

import 'package:aspnet_signalr/aspnet_signalr.dart';
import 'package:aspnet_signalr/src/application/default_reconnect_policy.dart';
import 'package:aspnet_signalr/src/application/invocation_tracker.dart';
import 'package:aspnet_signalr/src/application/keep_alive_monitor.dart';
import 'package:aspnet_signalr/src/application/reconnect_service.dart';
import 'package:aspnet_signalr/src/domain/entities/server_message.dart';
import 'package:test/test.dart';

void main() {
  group('InvocationTracker', () {
    test('register, complete, fail, failAll', () async {
      final t = InvocationTracker();
      final (a, fa) = t.register();
      final (b, fb) = t.register();
      final (c, fc) = t.register();
      expect([a, b, c], ['0', '1', '2']);
      expect(t.complete(const InvocationResult(id: 'P|1', progressId: '0')),
          isFalse);
      expect(t.complete(InvocationResult(id: a, result: 1)), isTrue);
      expect((await fa).result, 1);
      t.fail(b, 'x');
      await expectLater(fb, throwsA('x'));
      t.failAll('all');
      await expectLater(fc, throwsA('all'));
      expect(t.pendingCount, 0);
      expect(t.complete(const InvocationResult(id: '9')), isFalse);
    });
  });

  group('KeepAliveMonitor', () {
    test('slow once, then timeout', () async {
      var slow = 0;
      final timeout = Completer<void>();
      KeepAliveMonitor(
        timeout: const Duration(milliseconds: 120),
        onSlow: () => slow++,
        onTimeout: timeout.complete,
      ).start();
      await timeout.future.timeout(const Duration(seconds: 2));
      expect(slow, 1);
    });

    test('activity postpones the timeout', () async {
      var timedOut = false;
      final m = KeepAliveMonitor(
        timeout: const Duration(milliseconds: 150),
        onSlow: () {},
        onTimeout: () => timedOut = true,
      )..start();
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        m.markActivity();
      }
      expect(timedOut, isFalse);
      m.stop();
    });
  });

  group('policies', () {
    RetryContext ctx(int n, [Duration e = Duration.zero]) =>
        RetryContext(previousRetryCount: n, elapsed: e);

    test('default', () {
      const p = DefaultReconnectPolicy();
      expect(p.nextRetryDelay(ctx(0)), Duration.zero);
      expect(p.nextRetryDelay(ctx(3)), const Duration(seconds: 30));
      expect(p.nextRetryDelay(ctx(4)), isNull);
    });

    test('forever', () {
      const p = ForeverReconnectPolicy();
      expect(p.nextRetryDelay(ctx(0)), Duration.zero);
      expect(p.nextRetryDelay(ctx(1)), const Duration(seconds: 1));
      expect(p.nextRetryDelay(ctx(3)), const Duration(seconds: 4));
      expect(p.nextRetryDelay(ctx(100)), const Duration(seconds: 30));
    });

    test('protocol only', () {
      const p = ProtocolReconnectPolicy(Duration(seconds: 10));
      expect(p.nextRetryDelay(ctx(0)), Duration.zero);
      expect(p.nextRetryDelay(ctx(1)), const Duration(seconds: 2));
      expect(p.nextRetryDelay(ctx(1, const Duration(seconds: 10))), isNull);
    });
  });

  group('ReconnectService', () {
    test('reconnects inside the window, restarts after it', () async {
      var reconnects = 0;
      var restarts = 0;
      final service = ReconnectService(
        policy: const DefaultReconnectPolicy(
            delays: [Duration.zero, Duration.zero]),
        window: const Duration(seconds: 30),
        allowRestart: true,
        reconnectTransport: () async {
          reconnects++;
          if (reconnects == 1) throw 'first fails';
        },
        restart: () async => restarts++,
      );
      expect(await service.run(lastActive: DateTime.now()),
          ReconnectOutcome.reconnected);
      expect(reconnects, 2);

      final late = ReconnectService(
        policy: const DefaultReconnectPolicy(),
        window: const Duration(seconds: 1),
        allowRestart: true,
        reconnectTransport: () async => reconnects++,
        restart: () async => restarts++,
      );
      expect(
        await late.run(
          lastActive: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
        ReconnectOutcome.restarted,
      );
      expect(restarts, 1);
    });

    test('gives up and can be cancelled', () async {
      final noRestart = ReconnectService(
        policy: const DefaultReconnectPolicy(),
        window: Duration.zero,
        allowRestart: false,
        reconnectTransport: () async {},
        restart: () async {},
      );
      expect(await noRestart.run(lastActive: DateTime.now()),
          ReconnectOutcome.gaveUp);

      final slow = ReconnectService(
        policy: const DefaultReconnectPolicy(delays: [Duration(seconds: 30)]),
        window: const Duration(minutes: 1),
        allowRestart: true,
        reconnectTransport: () async {},
        restart: () async {},
      );
      final run = slow.run(lastActive: DateTime.now());
      slow.cancel();
      expect(await run, ReconnectOutcome.cancelled);
    });
  });
}
