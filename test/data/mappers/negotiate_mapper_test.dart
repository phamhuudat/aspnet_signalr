import 'dart:convert';

import 'package:aspnet_signalr/src/data/dtos/negotiate_response_dto.dart';
import 'package:aspnet_signalr/src/data/mappers/negotiate_mapper.dart';
import 'package:test/test.dart';

import '../../fixture_reader.dart';

Map<String, dynamic> _negotiateBody(String fixture) {
  final response = readFixture(fixture).firstWhere((e) => e.kind == 'response');
  final json = response.data.substring(response.data.indexOf('{'));
  return jsonDecode(json) as Map<String, dynamic>;
}

void main() {
  test('server without WebSockets (fixture)', () {
    final info = NegotiateResponseDto.fromJson(
      _negotiateBody(fixtureNames('a_negotiate').first),
    ).toEntity();
    expect(info.tryWebSockets, isFalse);
    expect(info.connectionToken, 'FAKE_TOKEN');
    expect(info.connectionId, startsWith('00000000-'));
    expect(info.keepAliveTimeout, const Duration(seconds: 20));
    expect(info.disconnectTimeout, const Duration(seconds: 30));
    expect(info.connectionTimeout, const Duration(seconds: 110));
    expect(info.transportConnectTimeout, const Duration(seconds: 5));
    expect(info.longPollDelay, Duration.zero);
    expect(info.protocolVersion, '1.5');
  });

  test('server with WebSockets (fixture)', () {
    final info = NegotiateResponseDto.fromJson(
      _negotiateBody(fixtureNames('c_negotiate').first),
    ).toEntity();
    expect(info.tryWebSockets, isTrue);
  });

  test('defaults and keep-alive disabled', () {
    final info = NegotiateResponseDto.fromJson({
      'ConnectionToken': 't',
      'ConnectionId': 'i',
      'KeepAliveTimeout': null,
      'TryWebSockets': 'true',
      'DisconnectTimeout': '12.5',
    }).toEntity();
    expect(info.keepAliveTimeout, isNull);
    expect(info.tryWebSockets, isTrue);
    expect(info.disconnectTimeout, const Duration(milliseconds: 12500));
    expect(info.transportConnectTimeout, const Duration(seconds: 5));
  });

  test('round trip', () {
    final dto = NegotiateResponseDto.fromJson({
      'Url': '/x',
      'ConnectionToken': 't',
      'ConnectionId': 'i',
      'KeepAliveTimeout': 20.0,
    });
    expect(NegotiateResponseDto.fromJson(dto.toJson()).toJson(), dto.toJson());
  });
}
