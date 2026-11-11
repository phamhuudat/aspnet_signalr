import 'package:aspnet_signalr/src/data/transports/sse/sse_parser.dart';
import 'package:test/test.dart';

import '../../fixture_reader.dart';

void main() {
  Future<List<String>> parse(List<String> lines) => Stream.fromIterable(lines)
      .transform(const SseEventTransformer())
      .toList();

  test('data lines, blank line dispatch, comments and fields', () async {
    expect(
      await parse([
        'data: initialized',
        '',
        ': comment',
        'id: 5',
        'event: message',
        'data:{"a":1}',
        '',
        'data: line1',
        'data: line2',
        '',
        'data: tail',
      ]),
      ['initialized', '{"a":1}', 'line1\nline2', 'tail'],
    );
  });

  test('replays the sanitized SSE fixtures', () async {
    for (final name in fixtureNames('_sse_')) {
      final lines = [
        for (final e in readFixture(name))
          if (e.kind == 'frame') e.data,
      ];
      final events = await parse(lines);
      expect(events.first, 'initialized', reason: name);
      expect(events[1], contains('"S":1'), reason: name);
      expect(
        events.skip(2).every((e) => e == '{}' || e.startsWith('{"C"')),
        isTrue,
        reason: name,
      );
    }
  });
}
