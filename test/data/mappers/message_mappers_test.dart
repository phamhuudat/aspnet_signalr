import 'package:aspnet_signalr/src/data/dtos/hub_invocation_dto.dart';
import 'package:aspnet_signalr/src/data/dtos/hub_result_dto.dart';
import 'package:aspnet_signalr/src/data/dtos/persistent_response_dto.dart';
import 'package:aspnet_signalr/src/data/mappers/message_mappers.dart';
import 'package:aspnet_signalr/src/domain/entities/hub_invocation.dart';
import 'package:test/test.dart';

void main() {
  test('invocation to DTO uses a numeric id and omits empty state', () {
    final json = const HubInvocation(
      hub: 'huba',
      method: 'add',
      args: [1, 2],
      id: '7',
    ).toDto().toJson();
    expect(json, {
      'H': 'huba',
      'M': 'add',
      'A': [1, 2],
      'I': 7,
    });
    final withState = const HubInvocation(
      hub: 'h',
      method: 'm',
      id: '1',
      state: {'a': 1},
    ).toDto().toJson();
    expect(withState['S'], {'a': 1});
    expect(HubInvocationDto.fromJson(withState).state, {'a': 1});
  });

  test('persistent response DTO round trip', () {
    const dto = PersistentResponseDto(
      messageId: 'c',
      initialized: true,
      groupsToken: 'g',
      longPollDelayMs: 10,
      messages: [
        {'H': 'h', 'M': 'm', 'A': []},
      ],
    );
    final entity = PersistentResponseDto.fromJson(dto.toJson()).toEntity();
    expect(entity.initialized, isTrue);
    expect(entity.messages.single.method, 'm');
    expect(entity.longPollDelay, const Duration(milliseconds: 10));
  });

  test('hub result DTO round trip', () {
    const dto = HubResultDto(id: '1', error: 'e', isHubException: true);
    final entity = HubResultDto.fromJson(dto.toJson()).toEntity();
    expect(entity.error, 'e');
    expect(entity.isHubException, isTrue);
  });
}
