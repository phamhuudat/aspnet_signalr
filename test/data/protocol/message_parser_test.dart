import 'package:aspnet_signalr/src/data/protocol/message_parser.dart';
import 'package:aspnet_signalr/src/domain/entities/server_message.dart';
import 'package:aspnet_signalr/src/domain/exceptions/signalr_exception.dart';
import 'package:test/test.dart';

import '../../fixture_reader.dart';

void main() {
  const parser = MessageParser();

  test('keep-alive, init, hub message, result, progress', () {
    expect(parser.parse('{}'), isA<KeepAliveMessage>());
    expect(parser.parse('   '), isNull);

    final init =
        parser.parse('{"C":"d-A,0|B,0","S":1,"M":[]}')! as PersistentResponse;
    expect(init.initialized, isTrue);
    expect(init.messageId, 'd-A,0|B,0');

    final msg = parser.parse(
      '{"C":"c","G":"g","T":1,"L":250,"M":[{"H":"HubA","M":"update",'
      '"A":[{"x":1},2]}, "raw"]}',
    )! as PersistentResponse;
    expect(msg.groupsToken, 'g');
    expect(msg.shouldReconnect, isTrue);
    expect(msg.longPollDelay, const Duration(milliseconds: 250));
    expect(msg.messages.single.hub, 'HubA');
    expect(msg.messages.single.args, [
      {'x': 1},
      2,
    ]);
    expect(msg.rawMessages, ['raw']);

    final err = parser.parse('{"I":"3","E":"bad","H":true,"D":{"a":1}}')!
        as InvocationResult;
    expect(err.id, '3');
    expect(err.hasError, isTrue);
    expect(err.isHubException, isTrue);
    expect(err.errorData, {'a': 1});

    final ok = parser.parse('{"I":"4","R":[1,2]}')! as InvocationResult;
    expect(ok.result, [1, 2]);
    expect(ok.hasError, isFalse);

    final progress =
        parser.parse('{"I":"P|1","P":{"I":"0","D":50}}')! as InvocationResult;
    expect(progress.isProgress, isTrue);
    expect(progress.progressId, '0');
    expect(progress.progress, 50);

    expect(
        parser.parse('{"D":1}'),
        isA<PersistentResponse>()
            .having((p) => p.disconnect, 'disconnect', true));
  });

  test('long polling padding is ignored', () {
    expect(parser.parse('      {"C":"x","M":[]}'), isA<PersistentResponse>());
  });

  test('invalid frames throw TransportException', () {
    expect(() => parser.parse('{oops'), throwsA(isA<TransportException>()));
    expect(() => parser.parse('[1]'), throwsA(isA<TransportException>()));
  });

  test('every frame of the sanitized fixtures parses', () {
    var frames = 0;
    var hubMessages = 0;
    for (final name in fixtureNames(RegExp('_(sse|ws|lp)_'))) {
      for (final e in readFixture(name)) {
        if (e.kind != 'frame' && e.kind != 'response') continue;
        var data = e.data;
        if (e.kind == 'response') {
          final space = data.indexOf(' ');
          if (space < 0) continue;
          data = data.substring(space + 1);
          if (!data.trimLeft().startsWith('{"C"')) continue;
        }
        if (data.startsWith('data: ')) data = data.substring(6);
        if (data.isEmpty || data == sseInitializedMarker) continue;
        final m = parser.parse(data);
        frames++;
        if (m is PersistentResponse) {
          hubMessages += m.messages.length;
          for (final h in m.messages) {
            expect(h.method, 'update');
            final payload = h.args.single as Map<String, dynamic>;
            expect(payload.keys, containsAll(['Channel', 'Change', 'Time']));
            expect(payload['Change'], isA<String>());
          }
        }
      }
    }
    expect(frames, greaterThan(10));
    expect(hubMessages, greaterThan(0));
  });
}
