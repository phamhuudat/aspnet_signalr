/// Pure Dart client for ASP.NET SignalR 2.x (not ASP.NET Core).
library;

export 'src/application/default_reconnect_policy.dart'
    show DefaultReconnectPolicy, ForeverReconnectPolicy;
export 'src/core/logger.dart'
    show LogLevel, NoopLogger, PrintLogger, SignalRLogger;
export 'src/domain/entities/connection_state.dart';
export 'src/domain/entities/proxy_config.dart';
export 'src/domain/entities/transport_type.dart';
export 'src/domain/exceptions/signalr_exception.dart';
export 'src/domain/policies/reconnect_policy.dart';
export 'src/presentation/hub_connection.dart';
export 'src/presentation/hub_connection_builder.dart';
export 'src/presentation/hub_connection_manager.dart';
export 'src/presentation/hub_proxy.dart';
