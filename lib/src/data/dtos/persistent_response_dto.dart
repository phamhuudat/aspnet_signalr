import 'json_helpers.dart';

/// A persistent response frame: `{C, M, S, T, D, G, L}`.
class PersistentResponseDto {
  /// Creates the DTO.
  const PersistentResponseDto({
    this.messageId,
    this.messages = const [],
    this.initialized = false,
    this.shouldReconnect = false,
    this.disconnect = false,
    this.groupsToken,
    this.longPollDelayMs,
  });

  /// Parses a frame.
  factory PersistentResponseDto.fromJson(Map<String, dynamic> json) =>
      PersistentResponseDto(
        messageId: readString(json['C']),
        messages:
            json['M'] is List ? List<Object?>.from(json['M'] as List) : [],
        initialized: readFlag(json['S']),
        shouldReconnect: readFlag(json['T']),
        disconnect: readFlag(json['D']),
        groupsToken: readString(json['G']),
        longPollDelayMs: readInt(json['L']),
      );

  final String? messageId;
  final List<Object?> messages;
  final bool initialized;
  final bool shouldReconnect;
  final bool disconnect;
  final String? groupsToken;
  final int? longPollDelayMs;

  /// Serializes the DTO.
  Map<String, dynamic> toJson() => {
        if (messageId != null) 'C': messageId,
        if (initialized) 'S': 1,
        if (shouldReconnect) 'T': 1,
        if (disconnect) 'D': 1,
        if (groupsToken != null) 'G': groupsToken,
        if (longPollDelayMs != null) 'L': longPollDelayMs,
        'M': messages,
      };
}
