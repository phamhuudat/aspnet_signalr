// Fails if anything that looks like real data is about to be committed.
//
// Scans every text file of the repository except the gitignored folders
// that are allowed to hold real data (test/fixtures/_raw/, tool/spike/,
// .sensitive-patterns). Company specific words live in the local,
// gitignored `.sensitive-patterns` file so that they never appear here.
@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

const _skipDirs = {
  '.git',
  '.dart_tool',
  'build',
  'coverage',
  'test/fixtures/_raw',
  'tool/spike',
};
const _skipFiles = {'.sensitive-patterns', 'pubspec.lock'};
const _textExtensions = {
  '.dart',
  '.md',
  '.yaml',
  '.yml',
  '.json',
  '.jsonl',
  '.txt',
  '.html',
  '.js',
  '.sh',
  '',
};

final _jwt = RegExp(r'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}');
final _guid = RegExp(
  r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
);
final _longDigits = RegExp(r'(?<![\d.])\d{9,12}(?![\d.])');
final _email = RegExp(r'[A-Za-z0-9._%+-]+@(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}');
final _base64 = RegExp(r'[A-Za-z0-9+/=]{201,}');

List<String> _localPatterns() {
  final file = File('.sensitive-patterns');
  if (!file.existsSync()) return const [];
  final out = <String>[];
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('map:')) {
      final real = line.substring(4).split('=>').first.trim().toLowerCase();
      // Short path fragments such as "/a/" are too generic to scan for.
      if (real.length > 5) out.add(real);
    } else {
      out.add(line.toLowerCase());
    }
  }
  return out;
}

Iterable<File> _files() sync* {
  for (final e in Directory('.').listSync(recursive: true)) {
    if (e is! File) continue;
    final path = e.path.replaceFirst(RegExp(r'^\./'), '');
    if (_skipDirs.any((d) => path == d || path.startsWith('$d/'))) continue;
    if (_skipFiles.contains(path)) continue;
    final dot = path.lastIndexOf('.');
    final slash = path.lastIndexOf('/');
    final ext = dot > slash ? path.substring(dot) : '';
    if (!_textExtensions.contains(ext)) continue;
    yield e;
  }
}

void main() {
  test('.gitignore keeps real data out of git', () {
    final ignore = File('.gitignore').readAsStringSync();
    for (final entry in [
      'test/fixtures/_raw/',
      'tool/spike/',
      '.sensitive-patterns',
    ]) {
      expect(ignore, contains(entry));
    }
  });

  test('no real data in committable files', () {
    final patterns = _localPatterns();
    final problems = <String>[];
    for (final file in _files()) {
      final path = file.path;
      final String text;
      try {
        text = file.readAsStringSync();
      } on FileSystemException {
        continue;
      }
      final lower = text.toLowerCase();
      for (final p in patterns) {
        if (lower.contains(p)) problems.add('$path: sensitive word "$p"');
      }
      if (_jwt.hasMatch(text)) problems.add('$path: JWT');
      for (final m in _guid.allMatches(text)) {
        if (!m[0]!.startsWith('00000000-')) {
          problems.add('$path: GUID ${m[0]}');
        }
      }
      final withoutFakeIds = text.replaceAll(_guid, '');
      for (final m in _longDigits.allMatches(withoutFakeIds)) {
        problems.add('$path: long number ${m[0]}');
      }
      for (final m in _email.allMatches(text)) {
        final domain = m[0]!.toLowerCase().split('@').last;
        if (domain != 'example.com' && !domain.endsWith('.example.com')) {
          problems.add('$path: email ${m[0]}');
        }
      }
      if (_base64.hasMatch(text)) problems.add('$path: long base64');
    }
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
