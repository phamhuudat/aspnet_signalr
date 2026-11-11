import 'dart:async';

/// Turns text lines of an `text/event-stream` body into event data strings.
///
/// Handles multi-line `data:` fields, comments (`:`), and ignores the `id`,
/// `event` and `retry` fields.
class SseEventTransformer extends StreamTransformerBase<String, String> {
  /// Creates the transformer.
  const SseEventTransformer();

  @override
  Stream<String> bind(Stream<String> lines) {
    final buffer = <String>[];
    return lines.transform(
      StreamTransformer<String, String>.fromHandlers(
        handleData: (line, sink) {
          if (line.isEmpty) {
            if (buffer.isNotEmpty) {
              sink.add(buffer.join('\n'));
              buffer.clear();
            }
            return;
          }
          if (line.startsWith(':')) return;
          final colon = line.indexOf(':');
          final field = colon < 0 ? line : line.substring(0, colon);
          var value = colon < 0 ? '' : line.substring(colon + 1);
          if (value.startsWith(' ')) value = value.substring(1);
          if (field == 'data') buffer.add(value);
        },
        handleDone: (sink) {
          if (buffer.isNotEmpty) sink.add(buffer.join('\n'));
          sink.close();
        },
      ),
    );
  }
}
