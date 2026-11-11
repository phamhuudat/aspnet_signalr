import '../../domain/entities/hub_invocation.dart';
import '../../domain/entities/hub_message.dart';
import '../../domain/entities/server_message.dart';
import '../dtos/hub_invocation_dto.dart';
import '../dtos/hub_message_dto.dart';
import '../dtos/hub_result_dto.dart';
import '../dtos/json_helpers.dart';
import '../dtos/persistent_response_dto.dart';

/// `HubMessageDto` to `HubMessage`.
extension HubMessageMapper on HubMessageDto {
  /// Maps to the entity.
  HubMessage toEntity() =>
      HubMessage(hub: hub, method: method, args: args, state: state);
}

/// `PersistentResponseDto` to `PersistentResponse`.
extension PersistentResponseMapper on PersistentResponseDto {
  /// Maps to the entity, splitting hub and raw messages.
  PersistentResponse toEntity() {
    final hubs = <HubMessage>[];
    final raw = <Object?>[];
    for (final m in messages) {
      if (HubMessageDto.matches(m)) {
        hubs.add(HubMessageDto.fromJson(readMap(m)!).toEntity());
      } else {
        raw.add(m);
      }
    }
    return PersistentResponse(
      messageId: messageId,
      messages: hubs,
      rawMessages: raw,
      initialized: initialized,
      shouldReconnect: shouldReconnect,
      disconnect: disconnect,
      groupsToken: groupsToken,
      longPollDelay: longPollDelayMs == null
          ? null
          : Duration(milliseconds: longPollDelayMs!),
    );
  }
}

/// `HubResultDto` to `InvocationResult`.
extension HubResultMapper on HubResultDto {
  /// Maps to the entity.
  InvocationResult toEntity() {
    final p = progress;
    if (p != null) {
      return InvocationResult(
        id: id,
        progressId: readString(p['I']),
        progress: p['D'],
      );
    }
    return InvocationResult(
      id: id,
      result: result,
      error: error,
      errorData: errorData,
      isHubException: isHubException,
      state: state,
    );
  }
}

/// `HubInvocation` to `HubInvocationDto`.
extension HubInvocationMapper on HubInvocation {
  /// Maps to the DTO.
  HubInvocationDto toDto() => HubInvocationDto(
        hub: hub,
        method: method,
        args: args,
        id: id,
        state: state,
      );
}
