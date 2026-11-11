import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/logger.dart';
import '../../domain/entities/proxy_config.dart';
import 'proxy_error_classifier_io.dart';
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
  IoProxyErrorClassifier? classifier;
  if (proxy != null) {
    final String Function(Uri uri) findProxy;
    if (proxy.useEnvironment) {
      final env = proxy.environment;
      findProxy =
          (uri) => HttpClient.findProxyFromEnvironment(uri, environment: env);
    } else {
      findProxy = (uri) => proxy.resolve(uri) ?? 'DIRECT';
    }
    native.findProxy = findProxy;
    classifier = IoProxyErrorClassifier(findProxy);
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
    classifyProxyError: classifier?.call,
  );
}
