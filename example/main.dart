// Three independent connections, like three market data feeds.
//
// Start the fake server first:
//   dart run tool/fake_server/main.dart
// then:
//   dart run example/main.dart
import 'package:aspnet_signalr/aspnet_signalr.dart';

Future<void> main() async {
  const url = 'http://localhost:8085';

  HubConnection feed(TransportType transport) => HubConnectionBuilder()
      .withUrl(url) // "/signalr" is appended (useDefaultPath: true)
      .withTransport(transport)
      .withAutomaticReconnect()
      .withLogger(const PrintLogger(level: LogLevel.info))
      .build();

  final a = feed(TransportType.webSockets);
  final b = feed(TransportType.serverSentEvents);
  final d = feed(TransportType.longPolling);

  // Hub proxies must be created BEFORE start().
  a.createHubProxy('HubA').on('update', (args) => print('A: ${args[0]}'));
  b.createHubProxy('HubB').on('update', (args) => print('B: ${args[0]}'));
  final hubD = d.createHubProxy('HubD')
    ..on('update', (args) => print('D: ${args[0]}'));

  final manager = HubConnectionManager()
    ..add('a', a)
    ..add('b', b)
    ..add('d', d);

  await manager.startAll();
  for (final name in manager.names) {
    print('$name connected with ${manager[name]!.transport}');
  }

  print('add(2, 3) = ${await hubD.invoke<int>('add', [2, 3])}');

  await Future<void>.delayed(const Duration(seconds: 3));
  await manager.stop('d'); // a and b keep running
  await Future<void>.delayed(const Duration(seconds: 2));
  await manager.stopAll();
}
