import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 会话摘要层的内存上限（对应方案第 7 节的结束记录总边界）。
/// 注意：活跃传输（非终态）的记录不参与裁剪，只删除最旧的终态记录。
const _maxEntries = 500;

/// 终态判定辅助：只有终态记录才可被裁剪，活跃记录必须保留（方案第 7 节）。
extension ConversationOutcomeTerminal on ConversationOutcome {
  bool get isTerminal => switch (this) {
    ConversationOutcome.preparing || ConversationOutcome.waiting || ConversationOutcome.transferring => false,
    _ => true,
  };
}

/// 会话摘要层的内存状态。
///
/// 三类数据职责不同，故意放在一起但语义分离：
/// - [peers]：设备展示信息（alias、deviceType），按 peerKey 唯一。历史不持久化"在线"状态。
/// - [entries]：全部会话记录（气泡），按 entryId 唯一，列表顺序为创建顺序（最旧在前）。
/// - [clearedEntryIds]：最小去重状态（tombstone）。用户清除记录后，晚到的进度/完成事件
///   不得把被清除的内容重新补回（方案第 7 节 + 不变量 10），因此清除时记录 entryId 而非直接丢弃。
class ConversationState {
  final List<ConversationPeer> peers;
  final List<ConversationEntry> entries;
  final Set<String> clearedEntryIds;

  const ConversationState({
    this.peers = const [],
    this.entries = const [],
    this.clearedEntryIds = const {},
  });
}

/// 会话摘要 provider：P2 仅内存，持久化属于 P8（届时复用本状态并串行落盘）。
///
/// 这里是第 5.3 节两个集成接口的落点：
/// - [EnsureTransferEntryAction]：实际 session 创建后登记设备、方向、文件摘要和 sessionId。
/// - [UpsertTransferSnapshotAction]：在明确状态事件与清理前同步更新内存摘要。
final conversationProvider = ReduxProvider<ConversationService, ConversationState>((ref) {
  return ConversationService();
});

class ConversationService extends ReduxNotifier<ConversationState> {
  @override
  ConversationState init() => const ConversationState();
}

/// 登记一次真实传输：upsert 设备信息，并创建对应的传输记录（气泡）。
///
/// 幂等性：同一 entryId（direction + localSessionId）重复 ensure 不会追加第二条记录，
/// 只更新设备展示信息（同一 fingerprint 换 IP、改名仍保持一个会话，方案 9.1）。
/// 若该 entryId 已被用户清除（tombstone），则不复活其内容（方案第 7 节）。
class EnsureTransferEntryAction extends ReduxAction<ConversationService, ConversationState> {
  final ConversationPeer peer;
  final ConversationDirection direction;
  final String localSessionId;
  final ConversationEntryKind kind;
  final List<ConversationFileSummary> files;
  final String? text;

  /// 初始结果默认 preparing；文字类可在登记时直接给 waiting 等更准确的阶段。
  final ConversationOutcome initialOutcome;

  EnsureTransferEntryAction({
    required this.peer,
    required this.direction,
    required this.localSessionId,
    required this.kind,
    this.files = const [],
    this.text,
    this.initialOutcome = ConversationOutcome.preparing,
  });

  @override
  ConversationState reduce() {
    final entryId = ConversationEntry.buildEntryId(direction, localSessionId);

    // 设备信息 upsert：peerKey 已存在时用最新的 alias/deviceType 覆盖展示字段，
    // 但不新增条目；临时 peerKey 天然互不相同，不会与稳定会话合并（不变量 6）。
    final peers = [...state.peers];
    final peerIndex = peers.indexWhere((p) => p.peerKey == peer.peerKey);
    if (peerIndex == -1) {
      peers.add(peer);
    } else {
      peers[peerIndex] = peer;
    }

    // 已被用户清除的记录不复活内容；但仍更新设备展示信息（peer 与记录职责分离）。
    if (state.clearedEntryIds.contains(entryId)) {
      return ConversationState(peers: peers, entries: state.entries, clearedEntryIds: state.clearedEntryIds);
    }

    final entries = [...state.entries];
    final existingIndex = entries.indexWhere((e) => e.entryId == entryId);
    if (existingIndex == -1) {
      // 草稿发送动作在拿到真实 sessionId 时创建记录，不另造乐观记录（方案 5.2）——
      // 因此本 action 只以真实 sessionId 为键创建唯一记录。
      entries.add(
        ConversationEntry(
          entryId: entryId,
          peerKey: peer.peerKey,
          direction: direction,
          localSessionId: localSessionId,
          kind: kind,
          outcome: initialOutcome,
          createdAt: DateTime.now().toUtc(),
          finishedAt: null,
          files: files,
          text: text,
          error: null,
        ),
      );
    }

    return ConversationState(peers: peers, entries: entries, clearedEntryIds: state.clearedEntryIds);
  }
}

/// 用最新快照整体替换某条传输记录（upsert 语义，方案 5.3 接口 2）。
///
/// - entryId 已存在 → 原位替换，气泡数量不变（重复终态事件不多一条，方案 9.1）。
/// - entryId 不存在且未被清除 → 追加（容忍先收到快照、后补登记的乱序场景）。
/// - entryId 已被用户清除 → 忽略，绝不复活（方案第 7 节）。
/// - 超出内存上限时只裁剪最旧的"终态"记录，活跃传输不裁剪（方案第 7 节）。
class UpsertTransferSnapshotAction extends ReduxAction<ConversationService, ConversationState> {
  final ConversationEntry entry;

  UpsertTransferSnapshotAction(this.entry);

  @override
  ConversationState reduce() {
    if (state.clearedEntryIds.contains(entry.entryId)) {
      return state;
    }

    final entries = [...state.entries];
    final index = entries.indexWhere((e) => e.entryId == entry.entryId);
    if (index == -1) {
      entries.add(entry);
      // 从最旧开始删除第一个终态记录，直到不超过上限；活跃记录跳过。
      while (entries.length > _maxEntries) {
        final evictIndex = entries.indexWhere((e) => e.outcome.isTerminal);
        if (evictIndex == -1) {
          // 全部活跃（极端情况）：宁可超限也不丢活跃传输。
          break;
        }
        entries.removeAt(evictIndex);
      }
    } else {
      // 原位替换：保持创建顺序，保证 UI 分组稳定
      entries[index] = entry;
    }

    return ConversationState(peers: state.peers, entries: entries, clearedEntryIds: state.clearedEntryIds);
  }
}

/// 清除单条记录。只清显示记录：不删真实文件、不取消任何传输（方案第 7 节 + 不变量 1/2）。
/// entryId 进入 tombstone 集合，阻止晚到的进度/完成事件重新补回内容。
class RemoveConversationEntryAction extends ReduxAction<ConversationService, ConversationState> {
  final String entryId;

  RemoveConversationEntryAction(this.entryId);

  @override
  ConversationState reduce() {
    final index = state.entries.indexWhere((e) => e.entryId == entryId);
    if (index == -1) {
      return state;
    }
    final entries = [...state.entries]..removeAt(index);
    final cleared = {...state.clearedEntryIds, entryId};
    return ConversationState(peers: state.peers, entries: entries, clearedEntryIds: cleared);
  }
}

/// 清除某个设备会话的全部记录（"清空当前会话"）。
/// 保留 peer 展示信息：设备可见性由 P3 显示投影层合并附近设备决定，本层不猜测。
class ClearPeerEntriesAction extends ReduxAction<ConversationService, ConversationState> {
  final String peerKey;

  ClearPeerEntriesAction(this.peerKey);

  @override
  ConversationState reduce() {
    final removed = state.entries.where((e) => e.peerKey == peerKey).map((e) => e.entryId).toSet();
    if (removed.isEmpty) {
      return state;
    }
    final entries = state.entries.where((e) => e.peerKey != peerKey).toList();
    final cleared = {...state.clearedEntryIds, ...removed};
    return ConversationState(peers: state.peers, entries: entries, clearedEntryIds: cleared);
  }
}

/// 清除全部记录（"清空全部会话"）。同样只清记录、不触碰文件与传输（方案第 7 节）。
class ClearAllEntriesAction extends ReduxAction<ConversationService, ConversationState> {
  @override
  ConversationState reduce() {
    if (state.entries.isEmpty) {
      return state;
    }
    final cleared = {...state.clearedEntryIds, ...state.entries.map((e) => e.entryId)};
    return ConversationState(peers: state.peers, entries: const [], clearedEntryIds: cleared);
  }
}
