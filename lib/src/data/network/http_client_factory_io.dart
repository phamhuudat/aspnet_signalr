import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/logger.dart';
import '../../domain/entities/proxy_config.dart';
import 'signalr_http_client.dart';

/// Creates the HTTP resources for one session (`dart:io`).
SignalRHttpClient createSignalRHttpClient({
  ProxyConfig? proxy,
  http.Client? userClient,
  SignalRLogger logger = const NoopLogger(),
}) {
  if (userClient != null) {
    return SignalRHttpClient(client: userClient, ownsClient: false);
  }
  final native = HttpClient();
  if (proxy != null) {
    if (proxy.useEnvironment) {
      final env = proxy.environment;
      native.findProxy =
          (uri) => HttpClient.findProxyFromEnvironment(uri, environment: env);
    } else {
      native.findProxy = (uri) => proxy.resolve(uri) ?? 'DIRECT';
    }
    if (proxy.allowBadCertificates) {
      logger.log(
        LogLevel.warning,
        'allowBadCertificates is enabled: TLS certificates are NOT verified',
      );
      native.badCertificateCallback = (cert, host, port) => true;
    }
    logger.log(LogLevel.debug, 'Using $proxy');
  }
  return SignalRHttpClient(
    client: IOClient(native),
    nativeClient: native,
    proxyConfigured: proxy != null,
  );
}
