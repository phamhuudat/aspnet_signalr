import '../../domain/entities/connection_info.dart';
import '../dtos/negotiate_response_dto.dart';

Duration? _seconds(double? s) =>
    s == null ? null : Duration(microseconds: (s * 1000000).round());

/// `NegotiateResponseDto` to `ConnectionInfo`.
extension NegotiateMapper on NegotiateResponseDto {
  /// Maps to the entity.
  ConnectionInfo toEntity() => ConnectionInfo(
        url: url,
        connectionId: connectionId,
        connectionToken: connectionToken,
        keepAliveTimeout: _seconds(keepAliveTimeout),
        disconnectTimeout:
            _seconds(disconnectTimeout) ?? const Duration(seconds: 30),
        connectionTimeout:
            _seconds(connectionTimeout) ?? const Duration(seconds: 110),
        tryWebSockets: tryWebSockets ?? false,
        protocolVersion: protocolVersion ?? '1.5',
        transportConnectTimeout:
            _seconds(transportConnectTimeout) ?? const Duration(seconds: 5),
        longPollDelay: _seconds(longPollDelay) ?? Duration.zero,
      );
}
