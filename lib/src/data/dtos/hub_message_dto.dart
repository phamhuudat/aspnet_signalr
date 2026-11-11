import 'json_helpers.dart';

/// One hub item of `M`: `{H, M, A, S}`.
class HubMessageDto {
  /// Creates the DTO.
  const HubMessageDto({
    required this.hub,
    required this.method,
    this.args = const [],
    this.state,
  });

  /// Parses one item of `M`.
  factory HubMessageDto.fromJson(Map<String, dynamic> json) => HubMessageDto(
        hub: readString(json['H']) ?? '',
        method: readString(json['M']) ?? '',
        args: json['A'] is List ? List<dynamic>.from(json['A'] as List) : [],
        state: readMap(json['S']),
      );

  /// Whether [json] looks like a hub message.
  static bool matches(Object? json) =>
      json is Map && json.containsKey('H') && json.containsKey('M');

  final String hub;
  final String method;
  final List<dynamic> args;
  final Map<String, dynamic>? state;

  /// Serializes the DTO.
  Map<String, dynamic> toJson() => {
        'H': hub,
        'M': method,
        'A': args,
        if (state != null) 'S': state,
      };
}
