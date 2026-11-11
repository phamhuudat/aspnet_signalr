import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import '../../core/logger.dart';
import '../../domain/entities/proxy_config.dart';
import 'signalr_http_client.dart';

/// Creates the HTTP resources for one session (Web).
SignalRHttpClient createSignalRHttpClient({
  ProxyConfig? proxy,
  http.Client? userClient,
  SignalRLogger logger = const NoopLogger(),
}) {
  if (proxy != null) {
    logger.log(
      LogLevel.warning,
      'ProxyConfig is ignored on the Web: the browser applies its own proxy',
    );
  }
  if (userClient != null) {
    return SignalRHttpClient(client: userClient, ownsClient: false);
  }
  return SignalRHttpClient(client: BrowserClient());
}
