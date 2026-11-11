import 'dart:convert';

import '../../domain/entities/server_message.dart';
import '../../domain/exceptions/signalr_exception.dart';
import '../dtos/hub_result_dto.dart';
import '../dtos/json_helpers.dart';
import '../dtos/persistent_response_dto.dart';
import '../mappers/message_mappers.dart';

/// The SSE marker sent before the first frame and after `/reconnect`.
const sseInitializedMarker = 'initialized';

/// Parses raw transport frames.
class MessageParser {
  /// Creates a parser.
  const MessageParser();

  /// Parses one frame. Returns `null` for blank input (long polling pads
  /// responses with whitespace).
  ServerMessage? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (e) {
      throw TransportException('Invalid frame: ${_short(text)}', cause: e);
    }
    final json = readMap(decoded);
    if (json == null) {
      throw TransportException('Unexpected frame: ${_short(text)}');
    }
    return parseJson(json);
  }

  /// Parses an already decoded frame.
  ServerMessage parseJson(Map<String, dynamic> json) {
    if (json.isEmpty) return const KeepAliveMessage();
    if (HubResultDto.matches(json)) {
      return HubResultDto.fromJson(json).toEntity();
    }
    return PersistentResponseDto.fromJson(json).toEntity();
  }

  static String _short(String s) =>
      s.length > 120 ? '${s.substring(0, 120)}...' : s;
}
