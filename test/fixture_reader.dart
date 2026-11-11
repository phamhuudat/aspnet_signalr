import 'dart:convert';
import 'dart:io';

/// One event of a sanitized fixture session.
class FixtureEvent {
  FixtureEvent(this.t, this.kind, this.data);
  final int t;
  final String kind;
  final String data;
}

/// Reads `test/fixtures/<name>`.
List<FixtureEvent> readFixture(String name) => [
      for (final line in File('test/fixtures/$name').readAsLinesSync())
        if (line.trim().isNotEmpty)
          () {
            final m = jsonDecode(line) as Map<String, dynamic>;
            return FixtureEvent(
                m['t'] as int, m['kind'] as String, m['data'] as String);
          }(),
    ];

/// Fixture file names matching [pattern].
List<String> fixtureNames(Pattern pattern) => Directory('test/fixtures')
    .listSync()
    .whereType<File>()
    .map((f) => f.uri.pathSegments.last)
    .where((n) => n.contains(pattern) && n.endsWith('.jsonl'))
    .toList()
  ..sort();
