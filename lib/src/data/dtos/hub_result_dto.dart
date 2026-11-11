import 'json_helpers.dart';

/// Invocation result: `{I, R, E, D, H, S}` or progress `{I: "P|n", P: {I, D}}`.
class HubResultDto {
  /// Creates the DTO.
  const HubResultDto({
    required this.id,
    this.result,
    this.error,
    this.errorData,
    this.isHubException = false,
    this.state,
    this.progress,
  });

  /// Parses a result frame.
  factory HubResultDto.fromJson(Map<String, dynamic> json) => HubResultDto(
        id: readString(json['I']) ?? '',
        result: json['R'],
        error: readString(json['E']),
        errorData: json['D'],
        isHubException: readFlag(json['H']),
        state: readMap(json['S']),
        progress: readMap(json['P']),
      );

  /// Whether [json] looks like an invocation result.
  static bool matches(Map<String, dynamic> json) => json.containsKey('I');

  final String id;
  final Object? result;
  final String? error;
  final Object? errorData;
  final bool isHubException;
  final Map<String, dynamic>? state;

  /// `P`: `{I, D}`.
  final Map<String, dynamic>? progress;

  /// Serializes the DTO.
  Map<String, dynamic> toJson() => {
        'I': id,
        if (result != null) 'R': result,
        if (error != null) 'E': error,
        if (errorData != null) 'D': errorData,
        if (isHubException) 'H': true,
        if (state != null) 'S': state,
        if (progress != null) 'P': progress,
      };
}
