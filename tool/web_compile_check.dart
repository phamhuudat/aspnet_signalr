// Compiled with `dart compile js` in CI to make sure the web connectors
// (EventSource, browser WebSocket, BrowserClient) build.
import 'package:aspnet_signalr/aspnet_signalr.dart';

void main() {
  final c = HubConnectionBuilder()
      .withUrl('https://example.com')
      .withTransport(TransportType.serverSentEvents)
      .withAutomaticReconnect()
      .build();
  c.createHubProxy('hub').on('m', (args) {});
  c.start();
}
