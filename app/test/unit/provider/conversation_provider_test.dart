import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

/// P2 会话摘要层（内存）测试。
/// 覆盖方案第 8 节 P2 完成门槛：重复事件、双向同 sessionId、清除后晚到事件。
void main() {
  ConversationPeer peer(String? fingerprint, {String alias = 'Alias'}) {
    return ConversationPeer(
      peerKey: ConversationPeer.peerKeyFor(fingerprint),
      fingerprint: fingerprint,
      alias: alias,
      deviceType: DeviceType.mobile,
    );
  }

  ConversationEntry snapshot({
    required ConversationDirection direction,
    required String localSessionId,
    required String peerKey,
    ConversationOutcome outcome = ConversationOutcome.finished,
  }) {
    return ConversationEntry(
      entryId: ConversationEntry.buildEntryId(direction, localSessionId),
      peerKey: peerKey,
      direction: direction,
      localSessionId: localSessionId,
      kind: ConversationEntryKind.text,
      outcome: outcome,
      createdAt: DateTime.utc(2026, 11, 5),
      finishedAt: DateTime.utc(2026, 11, 5, 12),
      files: const [],
      text: 'hello',
      error: null,
    );
  }

  group('EnsureTransferEntryAction', () {
    test('登记真实传输：创建一条记录并注册设备', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');

      service.dispatch(
        EnsureTransferEntryAction(
          peer: p,
          direction: ConversationDirection.send,
          localSessionId: 's-1',
          kind: ConversationEntryKind.text,
          text: 'hi',
        ),
      );

      expect(service.state.peers, [p]);
      expect(service.state.entries.length, 1);
      final entry = service.state.entries.first;
      expect(entry.entryId, 'send:s-1');
      expect(entry.peerKey, p.peerKey);
      expect(entry.outcome, ConversationOutcome.preparing);
      expect(entry.text, 'hi');
    });

    test('门槛①：同一 entryId 重复登记不追加第二条气泡', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');

      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.send, localSessionId: 's-1', kind: ConversationEntryKind.file),
      );
      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.send, localSessionId: 's-1', kind: ConversationEntryKind.file),
      );

      expect(service.state.entries.length, 1);
      expect(service.state.peers.length, 1);
    });

    test('门槛②：双向相同 localSessionId 生成两条独立记录', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');

      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.send, localSessionId: 'same', kind: ConversationEntryKind.text),
      );
      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.receive, localSessionId: 'same', kind: ConversationEntryKind.text),
      );

      expect(service.state.entries.length, 2);
      expect(service.state.entries.map((e) => e.entryId).toSet(), {'send:same', 'receive:same'});
      // 两条记录的 entryId 必须不同（方向前缀保证）
      expect(service.state.entries[0].entryId, isNot(service.state.entries[1].entryId));
    });

    test('同指纹改名/换身份来源仍是一个会话（peer 按 peerKey upsert）', () async {
      final service = ReduxNotifier.test(redux: ConversationService());

      service.dispatch(
        EnsureTransferEntryAction(
          peer: peer('AAA', alias: 'Old Name'),
          direction: ConversationDirection.send,
          localSessionId: 's-1',
          kind: ConversationEntryKind.text,
        ),
      );
      service.dispatch(
        EnsureTransferEntryAction(
          peer: peer('AAA', alias: 'New Name'),
          direction: ConversationDirection.send,
          localSessionId: 's-2',
          kind: ConversationEntryKind.text,
        ),
      );

      expect(service.state.peers.length, 1);
      expect(service.state.peers.single.alias, 'New Name');
      expect(service.state.entries.length, 2);
    });

    test('缺少可信身份的临时 peerKey 不与稳定会话合并（不变量 6）', () async {
      final service = ReduxNotifier.test(redux: ConversationService());

      service.dispatch(
        EnsureTransferEntryAction(
          peer: peer('AAA'),
          direction: ConversationDirection.receive,
          localSessionId: 's-1',
          kind: ConversationEntryKind.text,
        ),
      );
      service.dispatch(
        EnsureTransferEntryAction(
          peer: peer(null),
          direction: ConversationDirection.receive,
          localSessionId: 's-2',
          kind: ConversationEntryKind.text,
        ),
      );
      service.dispatch(
        EnsureTransferEntryAction(
          peer: peer('  '),
          direction: ConversationDirection.receive,
          localSessionId: 's-3',
          kind: ConversationEntryKind.text,
        ),
      );

      // 稳定 1 个 + 两个互不相同的临时身份
      expect(service.state.peers.length, 3);
      expect(service.state.peers.where((p) => p.isStable).length, 1);
    });
  });

  group('UpsertTransferSnapshotAction', () {
    test('门槛①：重复终态快照原位替换，不多一条气泡', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');
      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.send, localSessionId: 's-1', kind: ConversationEntryKind.text),
      );

      final finished = snapshot(direction: ConversationDirection.send, localSessionId: 's-1', peerKey: p.peerKey);
      service.dispatch(UpsertTransferSnapshotAction(finished));
      service.dispatch(UpsertTransferSnapshotAction(finished));

      expect(service.state.entries.length, 1);
      expect(service.state.entries.single.outcome, ConversationOutcome.finished);
    });

    test('快照可容忍乱序：未先 ensure 也能追加记录', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');

      service.dispatch(UpsertTransferSnapshotAction(snapshot(direction: ConversationDirection.receive, localSessionId: 'r-9', peerKey: p.peerKey)));

      expect(service.state.entries.length, 1);
      expect(service.state.entries.single.entryId, 'receive:r-9');
    });

    test('上限裁剪：只淘汰最旧终态记录，活跃传输保留', () async {
      // 499 条终态 + 1 条活跃（在最旧位置）= 500 条，再 upsert 一条新终态
      final active = snapshot(
        direction: ConversationDirection.send,
        localSessionId: 'active',
        peerKey: 'fp:aaa',
        outcome: ConversationOutcome.transferring,
      );
      final terminals = List.generate(499, (i) => snapshot(direction: ConversationDirection.send, localSessionId: 't-$i', peerKey: 'fp:aaa'));
      final service = ReduxNotifier.test(
        redux: ConversationService(),
        initialState: ConversationState(entries: [active, ...terminals]),
      );

      service.dispatch(UpsertTransferSnapshotAction(snapshot(direction: ConversationDirection.send, localSessionId: 'new', peerKey: 'fp:aaa')));

      expect(service.state.entries.length, 500);
      // 最旧的终态 t-0 被淘汰，活跃记录必须还在
      expect(service.state.entries.any((e) => e.localSessionId == 'active'), true);
      expect(service.state.entries.any((e) => e.localSessionId == 't-0'), false);
      expect(service.state.entries.any((e) => e.localSessionId == 'new'), true);
    });
  });

  group('清除与晚到事件（门槛③）', () {
    test('单条清除后，晚到的终态快照不得复活内容', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');
      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.send, localSessionId: 's-1', kind: ConversationEntryKind.text),
      );

      service.dispatch(RemoveConversationEntryAction('send:s-1'));
      expect(service.state.entries, isEmpty);

      // 晚到的进度/完成事件
      service.dispatch(UpsertTransferSnapshotAction(snapshot(direction: ConversationDirection.send, localSessionId: 's-1', peerKey: p.peerKey)));
      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.send, localSessionId: 's-1', kind: ConversationEntryKind.text),
      );

      expect(service.state.entries, isEmpty);
      // 但设备展示信息仍正常保留
      expect(service.state.peers.length, 1);
    });

    test('清空某设备后，该设备晚到事件不复活；其他设备不受影响', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final a = peer('AAA');
      final b = peer('BBB');
      service.dispatch(
        EnsureTransferEntryAction(peer: a, direction: ConversationDirection.send, localSessionId: 'a-1', kind: ConversationEntryKind.text),
      );
      service.dispatch(
        EnsureTransferEntryAction(peer: b, direction: ConversationDirection.send, localSessionId: 'b-1', kind: ConversationEntryKind.text),
      );

      service.dispatch(ClearPeerEntriesAction(a.peerKey));

      expect(service.state.entries.map((e) => e.peerKey), [b.peerKey]);

      service.dispatch(UpsertTransferSnapshotAction(snapshot(direction: ConversationDirection.send, localSessionId: 'a-1', peerKey: a.peerKey)));
      expect(service.state.entries.length, 1);
    });

    test('清空全部：记录清空、peers 保留、全部 entryId 进入去重状态', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');
      service.dispatch(
        EnsureTransferEntryAction(peer: p, direction: ConversationDirection.receive, localSessionId: 'r-1', kind: ConversationEntryKind.file),
      );

      service.dispatch(ClearAllEntriesAction());

      expect(service.state.entries, isEmpty);
      expect(service.state.peers.length, 1);
      expect(service.state.clearedEntryIds, {'receive:r-1'});

      service.dispatch(UpsertTransferSnapshotAction(snapshot(direction: ConversationDirection.receive, localSessionId: 'r-1', peerKey: p.peerKey)));
      expect(service.state.entries, isEmpty);
    });

    test('清除不存在的记录是无操作', () async {
      final service = ReduxNotifier.test(redux: ConversationService());

      service.dispatch(RemoveConversationEntryAction('send:none'));
      service.dispatch(ClearPeerEntriesAction('fp:zzz'));

      expect(service.state.entries, isEmpty);
      expect(service.state.clearedEntryIds, isEmpty);
    });
  });

  group('文件摘要随快照更新', () {
    test('批量文件放在同一气泡内，重试更新原卡片', () async {
      final service = ReduxNotifier.test(redux: ConversationService());
      final p = peer('AAA');

      service.dispatch(
        EnsureTransferEntryAction(
          peer: p,
          direction: ConversationDirection.send,
          localSessionId: 's-1',
          kind: ConversationEntryKind.file,
          files: [
            ConversationFileSummary(
              fileId: 'f1',
              fileName: 'a.txt',
              fileType: FileType.text,
              size: 10,
              outcome: ConversationFileOutcome.pending,
              path: null,
              savedToGallery: false,
              error: null,
            ),
            ConversationFileSummary(
              fileId: 'f2',
              fileName: 'b.png',
              fileType: FileType.image,
              size: 20,
              outcome: ConversationFileOutcome.pending,
              path: null,
              savedToGallery: false,
              error: null,
            ),
          ],
        ),
      );

      // 完成后快照：单文件失败如实记录，不伪成功
      service.dispatch(
        UpsertTransferSnapshotAction(
          ConversationEntry(
            entryId: 'send:s-1',
            peerKey: p.peerKey,
            direction: ConversationDirection.send,
            localSessionId: 's-1',
            kind: ConversationEntryKind.file,
            outcome: ConversationOutcome.partialFailure,
            createdAt: DateTime.utc(2026, 11, 5),
            finishedAt: DateTime.utc(2026, 11, 5, 12),
            files: [
              ConversationFileSummary(
                fileId: 'f1',
                fileName: 'a.txt',
                fileType: FileType.text,
                size: 10,
                outcome: ConversationFileOutcome.success,
                path: '/tmp/a.txt',
                savedToGallery: false,
                error: null,
              ),
              ConversationFileSummary(
                fileId: 'f2',
                fileName: 'b.png',
                fileType: FileType.image,
                size: 20,
                outcome: ConversationFileOutcome.failure,
                path: null,
                savedToGallery: false,
                error: 'disk full',
              ),
            ],
            text: null,
            error: null,
          ),
        ),
      );

      expect(service.state.entries.length, 1);
      final entry = service.state.entries.single;
      expect(entry.outcome, ConversationOutcome.partialFailure);
      expect(entry.files.length, 2);
      expect(entry.files.firstWhere((f) => f.fileId == 'f2').outcome, ConversationFileOutcome.failure);
    });
  });
}
