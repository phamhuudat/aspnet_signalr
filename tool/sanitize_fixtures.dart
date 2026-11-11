// Turns raw spike logs (test/fixtures/_raw/, gitignored) into anonymized
// fixtures (test/fixtures/). Only the STRUCTURE of the frames is kept: field
// names, types, message order and timing. Every value is replaced.
//
// Real names are mapped with the "map: real => fake" lines of the local,
// gitignored `.sensitive-patterns` file; anything unmapped falls back to
// generic names.
//
//   dart run tool/sanitize_fixtures.dart
import 'dart:convert';
import 'dart:io';

const rawDir = 'test/fixtures/_raw';
const outDir = 'test/fixtures';
const maxFramesPerStream = 12;

final _line = RegExp(r'^\[\s*(\d+)\] (\S+) (.*)$');
final _guid = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);

late final List<(String, String)> _maps;
late final List<String> _scan;

void _loadPatterns() {
  final file = File('.sensitive-patterns');
  final maps = <(String, String)>[];
  final scan = <String>[];
  if (file.existsSync()) {
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('map:')) {
        final parts = line.substring(4).split('=>');
        maps.add((parts[0].trim(), parts[1].trim()));
      } else {
        scan.add(line.toLowerCase());
      }
    }
  }
  maps.sort((a, b) => b.$1.length.compareTo(a.$1.length));
  _maps = maps;
  _scan = scan;
}

String _replaceNames(String s) {
  var out = s;
  for (final (real, fake) in _maps) {
    out = out.replaceAll(real, fake);
    out = out.replaceAll(real.toLowerCase(), fake.toLowerCase());
  }
  return out;
}

int _guidCounter = 0;
final _guidMap = <String, String>{};
String _fakeGuid(String real) => _guidMap.putIfAbsent(real, () {
      _guidCounter++;
      return '00000000-0000-0000-0000-${_guidCounter.toString().padLeft(12, '0')}';
    });

/// Keeps the cursor shape (`d-XXXX-Y,n|Z,n|W,n`) with fake ids.
String _fakeCursor(String c) {
  final parts = c.split('|');
  return [
    for (var i = 0; i < parts.length; i++)
      i == 0
          ? 'd-FAKE-A,${parts[i].split(',').last}'
          : '${String.fromCharCode(66 + i)},${parts[i].split(',').last}',
  ].join('|');
}

String _sanitizeUrl(String url) {
  var uri = Uri.parse(_replaceNames(url));
  final q = Map<String, String>.from(uri.queryParameters);
  if (q.containsKey('connectionToken')) q['connectionToken'] = 'FAKE_TOKEN';
  if (q.containsKey('messageId')) q['messageId'] = _fakeCursor(q['messageId']!);
  if (q.containsKey('groupsToken')) q['groupsToken'] = 'FAKE_GROUPS_TOKEN';
  if (q.containsKey('_')) q['_'] = '0';
  uri = uri.replace(
    scheme: uri.scheme,
    host: 'example.com',
    queryParameters: q.isEmpty ? null : q,
  );
  return uri.toString();
}

/// Fake price rows with the same structure (`[{RowID, Info: [[k, v]]}]`) or
/// index pairs (`[[name, value]]`).
String _fakeChange(String change, int seed) {
  Object? decoded;
  try {
    decoded = jsonDecode(change);
  } catch (_) {
    return '[]';
  }
  if (decoded is! List) return '[]';
  final symbols = ['AAA', 'BBB', 'CCC'];
  final out = <Object?>[];
  for (var i = 0; i < decoded.length && i < 3; i++) {
    final item = decoded[i];
    if (item is Map) {
      final info = (item['Info'] as List?) ?? const [];
      out.add({
        'RowID': symbols[i],
        'Info': [
          for (var j = 0; j < info.length && j < 4; j++)
            [j + 1, (info[j] as List).last is num ? (seed + j) * 1.5 : 'X'],
        ],
      });
    } else if (item is List) {
      out.add(['IDX_${symbols[i]}_Value', '${seed + i}.00']);
    }
  }
  return jsonEncode(out);
}

int _seed = 10;

Object? _sanitizeJson(Object? v, {String? key}) {
  if (v is Map) {
    final m = <String, Object?>{};
    for (final e in v.entries) {
      final k = '${e.key}';
      m[k] = _sanitizeJson(e.value, key: k);
    }
    if (m['Change'] is String) {
      m['Change'] = _fakeChange(m['Change']! as String, _seed++);
    }
    if (m.containsKey('Time')) {
      m['Time'] = '10:00:${(_seed % 60).toString().padLeft(2, '0')}';
    }
    if (m['C'] is String) m['C'] = _fakeCursor(m['C']! as String);
    if (m['G'] is String) m['G'] = 'FAKE_GROUPS_TOKEN';
    if (m.containsKey('ConnectionToken')) m['ConnectionToken'] = 'FAKE_TOKEN';
    if (m['ConnectionId'] is String) {
      m['ConnectionId'] = _fakeGuid(m['ConnectionId']! as String);
    }
    return m;
  }
  if (v is List) return [for (final x in v) _sanitizeJson(x)];
  if (v is String) {
    return _replaceNames(v).replaceAllMapped(_guid, (g) => _fakeGuid(g[0]!));
  }
  return v;
}

String _sanitizeFrame(String frame) {
  final text = frame.trim();
  final pad = frame.length - frame.trimLeft().length;
  try {
    final decoded = jsonDecode(text);
    return '${' ' * pad}${jsonEncode(_sanitizeJson(decoded))}';
  } catch (_) {
    return _replaceNames(text);
  }
}

class _Event {
  _Event(this.t, this.kind, this.data);
  final int t;
  final String kind;
  final String data;
  Map<String, Object> toJson() => {'t': t, 'kind': kind, 'data': data};
}

void main() {
  _loadPatterns();
  final streams = <String, List<_Event>>{};
  final requests = <String>[];
  final starts = <String, int>{};
  final sources = <String, String>{};
  final logs = Directory(rawDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.log'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (var fileIndex = 0; fileIndex < logs.length; fileIndex++) {
    final file = logs[fileIndex];
    for (final raw in file.readAsLinesSync()) {
      final m = _line.firstMatch(raw);
      if (m == null) continue;
      final t = int.parse(m[1]!);
      final tag = m[2]!;
      final rest = m[3]!;
      final parts = tag.split('/');
      final transport = parts.length > 1 ? parts[1] : 'negotiate';
      // Sources get neutral names by order of first appearance.
      final neutral = sources.putIfAbsent(
        parts.first,
        () => String.fromCharCode(97 + sources.length),
      );
      final key = '${neutral}_${transport}_${fileIndex + 1}';
      starts.putIfAbsent(key, () => t);
      final rel = t - starts[key]!;
      final list = streams.putIfAbsent(key, () => []);
      if (list.length >= maxFramesPerStream * 4) continue;
      if (rest.startsWith('GET ') ||
          rest.startsWith('POST ') ||
          rest.startsWith('WS ')) {
        final sp = rest.split(' ');
        final url = _sanitizeUrl(sp[1]);
        final body = sp.length > 2 ? sp.sublist(2).join(' ') : '';
        requests.add('${sp[0]} $url');
        list.add(_Event(rel, 'request',
            '${sp[0]} $url ${_sanitizeFrame(body)}'.trimRight()));
      } else if (rest.startsWith('<- ')) {
        final body =
            rest.replaceFirst(RegExp(r'^<- (\d+) ?(\S+;? ?\S*)? ?'), '');
        final code = RegExp(r'^<- (\d+)').firstMatch(rest)?[1] ?? '?';
        if (body.startsWith('x-powered')) continue;
        list.add(_Event(
            rel, 'response', '$code ${_sanitizeFrame(body)}'.trimRight()));
      } else if (parts.length > 2 &&
          (parts[2] == 'frame' || parts[2] == 'send')) {
        if (list.where((e) => e.kind == 'frame' && e.data.isNotEmpty).length >=
            maxFramesPerStream) {
          continue;
        }
        final decoded = jsonDecode(rest);
        final value = decoded is String ? decoded : rest;
        final kind = parts[2];
        if (value.startsWith('data: ')) {
          final payload = value.substring(6);
          list.add(_Event(
            rel,
            kind,
            payload == 'initialized'
                ? 'data: initialized'
                : 'data: ${_sanitizeFrame(payload)}',
          ));
        } else {
          list.add(_Event(rel, kind, _sanitizeFrame(value)));
        }
      }
    }
  }
  Directory(outDir).createSync(recursive: true);
  final written = <String>[];
  for (final e in streams.entries) {
    if (e.value.isEmpty) continue;
    final name = '$outDir/session_${e.key}.jsonl';
    File(name).writeAsStringSync(
      '${e.value.map((x) => jsonEncode(x.toJson())).join('\n')}\n',
    );
    written.add(name);
  }
  File('$outDir/requests.txt')
      .writeAsStringSync('${requests.toSet().join('\n')}\n');
  written.add('$outDir/requests.txt');

  // Self check: no sensitive pattern may survive.
  var leaks = 0;
  for (final path in written) {
    final text = File(path).readAsStringSync().toLowerCase();
    for (final p in _scan) {
      if (text.contains(p)) {
        stderr.writeln('LEAK "$p" in $path');
        leaks++;
      }
    }
  }
  if (leaks > 0) {
    for (final path in written) {
      File(path).deleteSync();
    }
    stderr.writeln('Aborted: $leaks leaks, outputs deleted');
    exit(1);
  }
  stdout.writeln('Wrote ${written.length} files:\n${written.join('\n')}');
}
