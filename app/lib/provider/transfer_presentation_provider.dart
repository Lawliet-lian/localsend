import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 每个发送 session 的展示路径存储（方案 5.3 / P6a）。
///
/// 关键约束：
/// - 按 sessionId 独立保存，绝不用"当前在哪个 tab"来推断运行中任务的展示模式；
/// - 只存在于 Dart 应用层内存：不进 isolate、不进协议、不持久化；
/// - [TransferPresentation.legacy] 是默认值，因此**只为非 legacy 的 session 记录条目**，
///   legacy 会话不占存储；
/// - session 清理（closeSession / clearAllSessions）时必须同步移除，防止映射泄漏。
final transferPresentationProvider = NotifierProvider<TransferPresentationNotifier, Map<String, TransferPresentation>>((ref) {
  return TransferPresentationNotifier();
});

class TransferPresentationNotifier extends Notifier<Map<String, TransferPresentation>> {
  TransferPresentationNotifier();

  @override
  Map<String, TransferPresentation> init() {
    return {};
  }

  /// 记录 [sessionId] 的展示路径；legacy 是默认值，无需存储。
  void set(String sessionId, TransferPresentation presentation) {
    if (presentation == TransferPresentation.legacy) {
      // 显式 legacy 也顺带清除可能存在的旧条目，保证 get 语义一致
      if (state.containsKey(sessionId)) {
        state = {...state}..remove(sessionId);
      }
      return;
    }
    state = {...state, sessionId: presentation};
  }

  /// 读取 [sessionId] 的展示路径；未记录时返回默认值 legacy。
  TransferPresentation get(String sessionId) {
    return state[sessionId] ?? TransferPresentation.legacy;
  }

  /// session 结束时同步移除映射。
  void remove(String sessionId) {
    if (state.containsKey(sessionId)) {
      state = {...state}..remove(sessionId);
    }
  }

  /// 清空全部映射（对应 clearAllSessions）。
  void clearAll() {
    state = {};
  }
}
