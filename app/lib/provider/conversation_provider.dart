import 'dart:convert';

import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('ConversationService');

/// 会话摘要层的内存上限（对应方案第 7 节的结束记录总边界）。
/// 注意：活跃传输（非终态）的记录不参与裁剪，只删除最旧的终态记录。
const _maxEntries = 500;

// ---- 持久化限额（P8，方案第 7 节：50 设备 / 500 结束记录 / 2 MiB / 单条有界摘要）----
const _maxPersistedPeers = 50;
const _maxPersistedEntries = 500;
const _maxPersistedBytes = 2 * 1024 * 1024; // 序列化内容有界（以 UTF-16 长度近似字节数）
const _maxPersistedTextLen = 2000; // 单条文字/错误超过此长度则截断并置标志

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

/// 会话摘要 provider：内存 upsert（P2）+ 有界持久化（P8，变更经 `after()` 串行落盘）。
///
/// 这里是第 5.3 节两个集成接口的落点：
/// - [EnsureTransferEntryAction]：实际 session 创建后登记设备、方向、文件摘要和 sessionId。
/// - [UpsertTransferSnapshotAction]：在明确状态事件与清理前同步更新内存摘要。
final conversationProvider = ReduxProvider<ConversationService, ConversationState>((ref) {
  return ConversationService(ref.read(persistenceProvider));
});

class ConversationService extends ReduxNotifier<ConversationState> {
  /// 可空持久化：null = 纯内存（既有内存测试零改动、无落盘副作用）；生产注入 PersistenceService。
  ConversationService([this._persistence]);

  final PersistenceService? _persistence;

  // 串行落盘状态：单调序号 + Future 链，实现"latest-wins、防旧写入覆盖新状态"（方案第 7 节）。
  int _seq = 0;
  Future<void> _queue = Future.value();

  // 历史隐私门控（P9a-2）：黑名单——只有"保存历史"开关关闭期间新建的记录才加入，使其永不落盘。
  // 采用黑名单而非白名单，是为了让默认（保存开启）行为与 P8 完全一致：集合默认空 → 全部可落盘。
  // 四条语义（方案第 7 节 / L226）：①关闭后新内容不落盘、②已有历史不删、③重开不补存关闭期间内容、
  // ④主动清除仍落盘删除。见 trackNewEntry / _toPersistable。
  final _nonPersistableEntryIds = <String>{};

  /// 当前是否允许把新记录写入磁盘；无持久化（纯内存测试）按允许处理，保证零副作用。
  bool get _saveToHistory => _persistence?.isSaveToHistory() ?? true;

  /// 登记一条"新建"（非原位替换）的会话记录：若此刻保存历史被关闭，则拉黑使其永不落盘。
  /// 重新开启也不会补存——黑名单标记一经加入即长期有效，直到该记录被主动清除。
  void trackNewEntry(String entryId) {
    if (!_saveToHistory) {
      _nonPersistableEntryIds.add(entryId);
    }
  }

  /// 记录被清除后其拉黑标记已无意义（内存已无该记录），一并移除以保持集合有界（语义 ④）。
  void forgetNewEntryGuard(String entryId) => _nonPersistableEntryIds.remove(entryId);

  /// 清空全部时重置拉黑集合。
  void resetNewEntryGuards() => _nonPersistableEntryIds.clear();

  /// 测试可见：等待所有已排队的落盘任务完成（after() 是 fire-and-forget，测试需 drain 事件循环）。
  Future<void> get persistQueue => _queue;

  @override
  ConversationState init() {
    final persistence = _persistence;
    // 无持久化（纯内存测试）→ 空会话
    if (persistence == null) {
      return const ConversationState();
    }
    // getConversationHistory 永不为 null：坏 JSON/截断/版本不符已在其内部容错为空信封
    final history = persistence.getConversationHistory();
    if (history.entries.isEmpty && history.peers.isEmpty) {
      return const ConversationState();
    }
    // 重启恢复：持久化时可能残留活跃（非终态）记录，一律转为 incomplete（"上次传输未完成"，
    // 不自动重发）；tombstone 不持久化，故重启后 clearedEntryIds 恒为空（门槛）。
    final entries = [
      for (final e in history.entries) e.outcome.isTerminal ? e : e.copyWith(outcome: ConversationOutcome.incomplete),
    ];
    return ConversationState(peers: history.peers, entries: entries, clearedEntryIds: const {});
  }

  /// 由某个变更 action 的 after() 调用：排入一次串行落盘。
  /// - 无持久化（纯内存测试）直接返回，零副作用；
  /// - 用序号合并：只有"最后一次变更"真正落盘，中间态的排队写入在轮到自己时发现已被更新而跳过；
  /// - 写入异常在链内部捕获并记脱敏日志，绝不抛出——传输/调用点不受影响（写入失败不阻断传输）。
  void schedulePersist() {
    final persistence = _persistence;
    if (persistence == null) {
      return;
    }
    final mySeq = ++_seq;
    _queue = _queue.then((_) async {
      // 已被更新的变更覆盖：跳过这次陈旧写入
      if (mySeq != _seq) {
        return;
      }
      try {
        await persistence.setConversationHistory(_toPersistable(state));
      } catch (e) {
        // 只记录失败事实，不打印文字正文/路径等敏感内容
        _logger.warning('Failed to persist conversation history (transfer unaffected)');
      }
    });
  }

  /// 把内存状态转换为有界、可持久化的 DTO：
  /// ① 单条文字/错误超限截断并登记 truncatedEntryIds；
  /// ② 记录数裁剪到 _maxPersistedEntries（只淘汰最旧终态，活跃记录保留）；
  /// ③ 设备数裁剪到 _maxPersistedPeers；
  /// ④ 序列化仍超 _maxPersistedBytes 时，继续从最旧终态记录淘汰直至达标。
  ConversationHistoryDto _toPersistable(ConversationState s) {
    // P9a-2 隐私门控：先剔除"保存关闭期间新建"的记录；已有（非拉黑）记录照常进入磁盘快照，
    // 因此关闭开关不会删除既有历史（语义 ②），关闭期间新内容也不落盘（语义 ①、③）。
    final persistableEntries = s.entries.where((e) => !_nonPersistableEntryIds.contains(e.entryId)).toList();

    // ① 截断过长文字/错误
    final truncatedIds = <String>[];
    var entries = <ConversationEntry>[];
    for (final e in persistableEntries) {
      final textTooLong = e.text != null && e.text!.length > _maxPersistedTextLen;
      final errorTooLong = e.error != null && e.error!.length > _maxPersistedTextLen;
      if (textTooLong || errorTooLong) {
        truncatedIds.add(e.entryId);
        entries.add(
          e.copyWith(
            text: textTooLong ? e.text!.substring(0, _maxPersistedTextLen) : e.text,
            error: errorTooLong ? e.error!.substring(0, _maxPersistedTextLen) : e.error,
          ),
        );
      } else {
        entries.add(e);
      }
    }

    // ② 记录数上限：从最旧开始淘汰终态记录，活跃记录不淘汰
    entries = _evictTerminals(entries, _maxPersistedEntries);

    // ③ 设备数上限：peers 按插入顺序，保留最近出现的 _maxPersistedPeers 个
    var peers = s.peers;
    if (peers.length > _maxPersistedPeers) {
      peers = peers.sublist(peers.length - _maxPersistedPeers);
    }

    // ④ 字节上限：编码后仍超限则继续淘汰最旧终态记录（保留至少 1 条，避免清空有效数据）
    var dto = ConversationHistoryDto(version: conversationHistoryVersion, peers: peers, entries: entries, truncatedEntryIds: truncatedIds);
    while (entries.length > 1 && _encodedByteLength(dto) > _maxPersistedBytes) {
      entries = _evictTerminals(entries, entries.length - 1);
      final remainingIds = entries.map((e) => e.entryId).toSet();
      dto = ConversationHistoryDto(
        version: conversationHistoryVersion,
        peers: peers,
        entries: entries,
        truncatedEntryIds: truncatedIds.where(remainingIds.contains).toList(),
      );
    }
    return dto;
  }

  /// 从最旧开始淘汰终态记录到 [targetLength]；活跃（非终态）记录跳过。全部活跃则原样返回（宁超限不丢活跃）。
  static List<ConversationEntry> _evictTerminals(List<ConversationEntry> entries, int targetLength) {
    final result = [...entries];
    while (result.length > targetLength) {
      final evictIndex = result.indexWhere((e) => e.outcome.isTerminal);
      if (evictIndex == -1) {
        break;
      }
      result.removeAt(evictIndex);
    }
    return result;
  }

  /// 估算序列化后的字节规模（以 UTF-16 字符长度近似，用于 2 MiB 有界判断）。
  static int _encodedByteLength(ConversationHistoryDto dto) {
    return jsonEncode(dto.toJson()).length;
  }
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
  final bool? encrypted;

  /// 初始结果默认 preparing；文字类可在登记时直接给 waiting 等更准确的阶段。
  final ConversationOutcome initialOutcome;

  EnsureTransferEntryAction({
    required this.peer,
    required this.direction,
    required this.localSessionId,
    required this.kind,
    this.files = const [],
    this.text,
    this.encrypted,
    this.initialOutcome = ConversationOutcome.preparing,
  });

  // P8：登记后串行落盘（写入失败不阻断；纯内存测试无副作用）。
  @override
  void after() => notifier.schedulePersist();

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
          encrypted: encrypted,
          createdAt: DateTime.now().toUtc(),
          finishedAt: null,
          files: files,
          text: text,
          error: null,
        ),
      );
      // 新建记录登记持久化归属（保存关闭期间创建的将拉黑，P9a-2）。
      notifier.trackNewEntry(entryId);
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

  // P8：快照变更后串行落盘；重复终态事件原位替换，不额外追加磁盘记录。
  @override
  void after() => notifier.schedulePersist();

  @override
  ConversationState reduce() {
    if (state.clearedEntryIds.contains(entry.entryId)) {
      return state;
    }

    final entries = [...state.entries];
    final index = entries.indexWhere((e) => e.entryId == entry.entryId);
    if (index == -1) {
      entries.add(entry);
      // 快照先到、补登记的新记录同样纳入隐私门控（P9a-2）。
      notifier.trackNewEntry(entry.entryId);
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

  // P8：删除也走同一串行队列，防未完成的旧保存把已删记录写回（tombstone 本身不落盘）。
  @override
  void after() => notifier.schedulePersist();

  @override
  ConversationState reduce() {
    final index = state.entries.indexWhere((e) => e.entryId == entryId);
    if (index == -1) {
      return state;
    }
    final entries = [...state.entries]..removeAt(index);
    final cleared = {...state.clearedEntryIds, entryId};
    notifier.forgetNewEntryGuard(entryId); // 清除后拉黑标记失去意义（P9a-2 语义 ④）
    return ConversationState(peers: state.peers, entries: entries, clearedEntryIds: cleared);
  }
}

/// 清除某个设备会话的全部记录（"清空当前会话"）。
/// 保留 peer 展示信息：设备可见性由 P3 显示投影层合并附近设备决定，本层不猜测。
class ClearPeerEntriesAction extends ReduxAction<ConversationService, ConversationState> {
  final String peerKey;

  ClearPeerEntriesAction(this.peerKey);

  // P8：清空某设备后走同一队列落盘，防陈旧写入把已清记录写回。
  @override
  void after() => notifier.schedulePersist();

  @override
  ConversationState reduce() {
    final removed = state.entries.where((e) => e.peerKey == peerKey).map((e) => e.entryId).toSet();
    if (removed.isEmpty) {
      return state;
    }
    final entries = state.entries.where((e) => e.peerKey != peerKey).toList();
    final cleared = {...state.clearedEntryIds, ...removed};
    for (final id in removed) {
      // 被清记录的拉黑标记一并移除（P9a-2 语义 ④）
      notifier.forgetNewEntryGuard(id);
    }
    return ConversationState(peers: state.peers, entries: entries, clearedEntryIds: cleared);
  }
}

/// 清除全部记录（"清空全部会话"）。同样只清记录、不触碰文件与传输（方案第 7 节）。
class ClearAllEntriesAction extends ReduxAction<ConversationService, ConversationState> {
  // P8：清空全部同样走串行队列落盘。
  @override
  void after() => notifier.schedulePersist();

  @override
  ConversationState reduce() {
    if (state.entries.isEmpty) {
      return state;
    }
    final cleared = {...state.clearedEntryIds, ...state.entries.map((e) => e.entryId)};
    notifier.resetNewEntryGuards(); // 全部清空时重置拉黑集合（P9a-2）
    return ConversationState(peers: state.peers, entries: const [], clearedEntryIds: cleared);
  }
}
