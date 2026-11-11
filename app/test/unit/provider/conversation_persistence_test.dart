import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

import '../../mocks.mocks.dart';

/// P8：会话摘要层的有界持久化行为测试（方案第 7 节门槛：写入顺序、截断、清空不复活、坏数据容错）。
/// 用 MockPersistenceService 隔离真实存储；内存语义仍由 reduce 决定，落盘经 after() 串行调度。
void main() {
  late MockPersistenceService persistence;

  setUp(() {
    persistence = MockPersistenceService();
    // 默认无历史：init() 走空信封（纯内存起点），落盘默认 no-op（nice mock 返回 Future.value）
    when(persistence.getConversationHistory()).thenReturn(ConversationHistoryDto.empty());
    // P9a-2：复现生产默认的"保存历史"开启，使既有落盘用例行为与真实环境一致
    // （隐私门控采用黑名单，默认不拉黑；关闭保存的场景在下方专项 group 内单独 stub）。
    when(persistence.isSaveToHistory()).thenReturn(true);
  });

  ConversationPeer peer(String fp) {
    return ConversationPeer(
      peerKey: ConversationPeer.peerKeyFor(fp),
      fingerprint: fp,
      alias: 'A-$fp',
      deviceType: DeviceType.mobile,
    );
  }

  ConversationEntry snapshot(
    String id, {
    String peerKey = 'fp:aaa',
    ConversationOutcome outcome = ConversationOutcome.finished,
  }) {
    return ConversationEntry(
      entryId: ConversationEntry.buildEntryId(ConversationDirection.send, id),
      peerKey: peerKey,
      direction: ConversationDirection.send,
      localSessionId: id,
      kind: ConversationEntryKind.text,
      outcome: outcome,
      createdAt: DateTime.utc(2026, 11, 6),
      finishedAt: DateTime.utc(2026, 11, 6, 12),
      files: const [],
      text: 'hi $id',
      error: null,
    );
  }

  void ensureSend(ReduxNotifierTester<ConversationState> service, String id, {ConversationPeer? p, String? text}) {
    service.dispatch(
      EnsureTransferEntryAction(
        peer: p ?? peer('AAA'),
        direction: ConversationDirection.send,
        localSessionId: id,
        kind: ConversationEntryKind.text,
        text: text ?? 'hi $id',
      ),
    );
  }

  ConversationService svcOf(ReduxNotifierTester<ConversationState> service) => service.notifier as ConversationService;

  /// 等待 after() 里排队的所有落盘任务完成（fire-and-forget 需 drain 事件循环）。
  Future<void> flush(ReduxNotifierTester<ConversationState> service) => svcOf(service).persistQueue;

  ConversationHistoryDto lastWritten() => verify(persistence.setConversationHistory(captureAny)).captured.last as ConversationHistoryDto;

  test('linking identities preserves both histories and persists the new peer', () async {
    final old = peer('OLD');
    final current = peer('NEW');
    final service = ReduxNotifier.test(
      redux: ConversationService(persistence),
      initialState: ConversationState(
        peers: [old, current],
        entries: [
          snapshot('old', peerKey: old.peerKey),
          snapshot('new', peerKey: current.peerKey),
        ],
      ),
    );
    await service.dispatchAsync(RelinkConversationAction(oldPeer: old, newPeer: current));
    expect(service.state.peers.map((p) => p.peerKey), [current.peerKey]);
    expect(service.state.entries.map((e) => e.peerKey), [current.peerKey, current.peerKey]);
    expect(lastWritten().entries.map((e) => e.peerKey), [current.peerKey, current.peerKey]);
  });

  group('写入与串行合并', () {
    test('登记后落盘：dto 含该记录', () async {
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      ensureSend(service, 's-1');
      await flush(service);

      final dto = lastWritten();
      expect(dto.version, conversationHistoryVersion);
      expect(dto.entries.map((e) => e.entryId), ['send:s-1']);
      expect(dto.peers.map((e) => e.peerKey), ['fp:aaa']);
    });

    test('门槛：连续多次变更串行合并，只落最后一次状态（latest-wins，防旧覆盖新）', () async {
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      ensureSend(service, 's-1');
      ensureSend(service, 's-2');
      ensureSend(service, 's-3');
      await flush(service);

      // 陈旧写入被序号守卫跳过：恰好落盘一次
      // 单次 verify 同时取回捕获参数，既断言次数又断言内容，避免对同一调用重复 verify
      final captured = verify(persistence.setConversationHistory(captureAny)).captured;
      expect(captured.length, 1);
      expect((captured.last as ConversationHistoryDto).entries.length, 3);
    });
  });

  group('重启恢复（门槛）', () {
    test('活跃（非终态）记录恢复为 incomplete，不自动重发', () async {
      when(persistence.getConversationHistory()).thenReturn(
        ConversationHistoryDto(
          version: conversationHistoryVersion,
          peers: [peer('AAA')],
          entries: [snapshot('s-1', outcome: ConversationOutcome.transferring)],
        ),
      );

      final service = ReduxNotifier.test(redux: ConversationService(persistence));

      expect(service.state.entries.single.outcome, ConversationOutcome.incomplete);
      expect(service.state.clearedEntryIds, isEmpty);
    });

    test('门槛：清空后不落盘 tombstone；重启后 clearedEntryIds 为空、被清记录不复活', () async {
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      ensureSend(service, 's-1');
      await flush(service);
      service.dispatch(RemoveConversationEntryAction('send:s-1'));
      await flush(service);

      // 落盘的 dto 已无该记录，且本就不含 tombstone 字段
      final dto = lastWritten();
      expect(dto.entries, isEmpty);

      // 用该 dto 模拟"重启"：内存清除状态不应跨重启复活
      when(persistence.getConversationHistory()).thenReturn(dto);
      final restarted = ReduxNotifier.test(redux: ConversationService(persistence));
      expect(restarted.state.entries, isEmpty);
      expect(restarted.state.clearedEntryIds, isEmpty); // 门槛：tombstone 重启应为空
    });
  });

  group('写入失败与有界', () {
    test('门槛：落盘抛异常不向上传播、内存状态照常更新（写入失败不阻断传输）', () async {
      when(persistence.setConversationHistory(any)).thenThrow(Exception('disk full'));
      final service = ReduxNotifier.test(redux: ConversationService(persistence));

      ensureSend(service, 's-1');
      await flush(service); // 不应 throw 到测试

      expect(service.state.entries.length, 1);
    });

    test('超长文字：落盘截断为有界摘要并置截断标志，内存保留完整', () async {
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      ensureSend(service, 's-1', text: 'x' * 3000);
      await flush(service);

      final dto = lastWritten();
      expect(dto.entries.single.text!.length, 2000);
      expect(dto.truncatedEntryIds, ['send:s-1']);
      expect(service.state.entries.single.text!.length, 3000); // 内存不截断
    });

    test('设备上限：落盘裁剪到 50 个对端', () async {
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      for (var i = 0; i < 51; i++) {
        ensureSend(service, 's-$i', p: peer('FP$i'));
      }
      await flush(service);

      expect(service.state.peers.length, 51); // 内存不裁剪 peers
      expect(lastWritten().peers.length, 50); // 落盘裁剪
    });

    test('记录上限：落盘裁剪到 500 条（只淘汰最旧终态，活跃记录保留）', () async {
      final terminals = List.generate(501, (i) => snapshot('t-$i'));
      final service = ReduxNotifier.test(
        redux: ConversationService(persistence),
        initialState: ConversationState(peers: [peer('AAA')], entries: terminals),
      );
      ensureSend(service, 'new'); // 追加一条活跃记录（preparing）
      await flush(service);

      final dto = lastWritten();
      expect(dto.entries.length, 500);
      expect(dto.entries.any((e) => e.localSessionId == 'new'), isTrue); // 活跃不淘汰
      expect(dto.entries.any((e) => e.localSessionId == 't-0'), isFalse); // 最旧终态被淘汰
    });
  });

  group('隐私门控（P9a-2：复用 saveToHistory 开关）', () {
    test('语义①：关闭保存后新内容不落盘，但当前运行内存仍可显示', () async {
      when(persistence.isSaveToHistory()).thenReturn(false);
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      ensureSend(service, 's-1');
      await flush(service);

      expect(service.state.entries.length, 1); // 内存仍显示（当前运行可见）
      expect(lastWritten().entries, isEmpty); // 关闭期间新建被拉黑 → 落盘快照为空
    });

    test('语义③：重新开启后不把关闭期间的临时内容补存进去', () async {
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      when(persistence.isSaveToHistory()).thenReturn(false);
      ensureSend(service, 's-off'); // 关闭期间新建 → 拉黑
      when(persistence.isSaveToHistory()).thenReturn(true);
      ensureSend(service, 's-on'); // 开启后新建 → 可存
      await flush(service);

      final dto = lastWritten();
      expect(dto.entries.map((e) => e.entryId), ['send:s-on']); // 只含重开后的记录
    });

    test('语义②：关闭保存不会删除已有历史（重启恢复的记录仍照常落盘）', () async {
      when(persistence.getConversationHistory()).thenReturn(
        ConversationHistoryDto(
          version: conversationHistoryVersion,
          peers: [peer('AAA')],
          entries: [snapshot('old')],
        ),
      );
      when(persistence.isSaveToHistory()).thenReturn(false);
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      ensureSend(service, 'new'); // 关闭期间新建 → 拉黑
      await flush(service);

      final dto = lastWritten();
      expect(dto.entries.map((e) => e.entryId), contains('send:old')); // 已有历史保留
      expect(dto.entries.any((e) => e.localSessionId == 'new'), isFalse); // 新内容不落盘
    });

    test('语义④：即便关闭保存，主动清除仍落盘删除对应磁盘记录', () async {
      final service = ReduxNotifier.test(redux: ConversationService(persistence));
      ensureSend(service, 's-1'); // 开启期间新建 → 落盘含 s-1
      await flush(service);
      expect(lastWritten().entries.map((e) => e.entryId), ['send:s-1']);

      when(persistence.isSaveToHistory()).thenReturn(false); // 关闭保存
      service.dispatch(RemoveConversationEntryAction('send:s-1'));
      await flush(service);

      expect(lastWritten().entries, isEmpty); // 清除操作照常写盘（删除生效）
    });
  });
}
