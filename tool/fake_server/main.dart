// Runs the fake SignalR 2.x server: dart run tool/fake_server/main.dart [port]
import 'dart:async';
import 'dart:io';

import 'fake_signalr_server.dart';

Future<void> main(List<String> args) async {
  final port = args.isEmpty ? 8085 : int.parse(args.first);
  final server = FakeSignalRServer();
  await server.start(port: port);
  stdout.writeln('Fake SignalR server on ${server.url}/signalr');
  var tick = 0;
  Timer.periodic(const Duration(seconds: 1), (_) {
    tick++;
    for (final hub in ['HubA', 'HubB', 'HubD']) {
      server.broadcast(hub, 'update', [
        {'symbol': 'AAA', 'price': 10 + tick % 5, 'hub': hub},
      ]);
    }
  });
  await ProcessSignal.sigint.watch().first;
  await server.close();
  exit(0);
}
