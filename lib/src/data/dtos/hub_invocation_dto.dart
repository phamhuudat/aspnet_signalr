/// Client to server invocation: `{H, M, A, I, S}`.
class HubInvocationDto {
  /// Creates the DTO.
  const HubInvocationDto({
    required this.hub,
    required this.method,
    required this.args,
    required this.id,
    this.state,
  });

  /// Parses an invocation (used by the fake server).
  factory HubInvocationDto.fromJson(Map<String, dynamic> json) =>
      HubInvocationDto(
        hub: '${json['H']}',
        method: '${json['M']}',
        args: json['A'] is List ? List<Object?>.from(json['A'] as List) : [],
        id: '${json['I']}',
        state: json['S'] is Map
            ? Map<String, dynamic>.from(json['S'] as Map)
            : null,
      );

  final String hub;
  final String method;
  final List<Object?> args;
  final String id;
  final Map<String, dynamic>? state;

  /// Serializes the DTO.
  Map<String, dynamic> toJson() => {
        'H': hub,
        'M': method,
        'A': args,
        'I': int.tryParse(id) ?? id,
        if (state != null && state!.isNotEmpty) 'S': state,
      };
}
