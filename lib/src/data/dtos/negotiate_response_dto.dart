import 'json_helpers.dart';

/// Body of `GET /negotiate`.
class NegotiateResponseDto {
  /// Creates the DTO.
  const NegotiateResponseDto({
    required this.connectionToken,
    required this.connectionId,
    this.url,
    this.keepAliveTimeout,
    this.disconnectTimeout,
    this.connectionTimeout,
    this.tryWebSockets,
    this.protocolVersion,
    this.transportConnectTimeout,
    this.longPollDelay,
  });

  /// Parses the JSON body.
  factory NegotiateResponseDto.fromJson(Map<String, dynamic> json) =>
      NegotiateResponseDto(
        url: readString(json['Url']),
        connectionToken: readString(json['ConnectionToken']) ?? '',
        connectionId: readString(json['ConnectionId']) ?? '',
        keepAliveTimeout: readDouble(json['KeepAliveTimeout']),
        disconnectTimeout: readDouble(json['DisconnectTimeout']),
        connectionTimeout: readDouble(json['ConnectionTimeout']),
        tryWebSockets: json['TryWebSockets'] == null
            ? null
            : readFlag(json['TryWebSockets']),
        protocolVersion: readString(json['ProtocolVersion']),
        transportConnectTimeout: readDouble(json['TransportConnectTimeout']),
        longPollDelay: readDouble(json['LongPollDelay']),
      );

  final String? url;
  final String connectionToken;
  final String connectionId;

  /// Seconds.
  final double? keepAliveTimeout;
  final double? disconnectTimeout;
  final double? connectionTimeout;
  final bool? tryWebSockets;
  final String? protocolVersion;
  final double? transportConnectTimeout;
  final double? longPollDelay;

  /// Serializes the DTO (used by tests and the fake server).
  Map<String, dynamic> toJson() => {
        'Url': url,
        'ConnectionToken': connectionToken,
        'ConnectionId': connectionId,
        'KeepAliveTimeout': keepAliveTimeout,
        'DisconnectTimeout': disconnectTimeout,
        'ConnectionTimeout': connectionTimeout,
        'TryWebSockets': tryWebSockets,
        'ProtocolVersion': protocolVersion,
        'TransportConnectTimeout': transportConnectTimeout,
        'LongPollDelay': longPollDelay,
      };
}
