import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:test/test.dart';

/// P1 完成门槛：序列化、去重键、空身份三组合同测试。
void main() {
  group('ConversationPeer 设备键', () {
    test('同一指纹（含大小写差异）派生同一稳定 peerKey', () {
      final keyA = ConversationPeer.peerKeyFor('ABCD1234');
      final keyB = ConversationPeer.peerKeyFor('abcd1234');

      expect(keyA, keyB);
      expect(keyA, ConversationPeer.stablePeerKey('ABCD1234'));
    });

    test('不同指纹派生不同 peerKey（同名不同设备不合并）', () {
      expect(ConversationPeer.peerKeyFor('FINGERPRINT-A'), isNot(ConversationPeer.peerKeyFor('FINGERPRINT-B')));
    });

    test('空身份产生互不相同的临时键，且不与稳定键合并', () {
      final nullKey = ConversationPeer.peerKeyFor(null);
      final emptyKey = ConversationPeer.peerKeyFor('');
      final blankKey = ConversationPeer.peerKeyFor('   ');

      // 临时键两两不同：缺少可信身份时绝不自动合并到任何已有会话
      expect(nullKey, isNot(emptyKey));
      expect(nullKey, isNot(blankKey));
      expect(emptyKey, isNot(blankKey));

      // 临时键不等于任何稳定键
      expect(nullKey, isNot(ConversationPeer.peerKeyFor('ABCD')));
    });

    test('isStable 只在指纹可信且非空时为 true', () {
      final stable = ConversationPeer(peerKey: ConversationPeer.peerKeyFor('ABCD'), fingerprint: 'ABCD', alias: 'a', deviceType: DeviceType.mobile);
      final temporary = ConversationPeer(peerKey: ConversationPeer.temporaryPeerKey(), fingerprint: null, alias: 't', deviceType: DeviceType.desktop);
      final blank = ConversationPeer(peerKey: ConversationPeer.temporaryPeerKey(), fingerprint: '  ', alias: 'b', deviceType: DeviceType.web);

      expect(stable.isStable, isTrue);
      expect(temporary.isStable, isFalse);
      expect(blank.isStable, isFalse);
    });

    test('Map 与字符串序列化往返一致', () {
      const peer = ConversationPeer(
        peerKey: 'fp:abcd1234',
        fingerprint: 'ABCD1234',
        alias: 'LawlietPC',
        deviceType: DeviceType.desktop,
      );

      // 仓库约定：fromJson/toJson 是 Map 转换器，deserialize/serialize 是字符串转换器
      final viaMap = ConversationPeer.fromJson(peer.toJson());
      expect(viaMap, peer);

      final viaString = ConversationPeerMapper.deserialize(peer.serialize());
      expect(viaString, peer);
    });
  });

  group('ConversationEntry 去重键', () {
    test('同方向同 sessionId 生成相同 entryId（重复事件 upsert 的依据）', () {
      final a = ConversationEntry.buildEntryId(ConversationDirection.send, 'session-1');
      final b = ConversationEntry.buildEntryId(ConversationDirection.send, 'session-1');
      expect(a, b);
    });

    test('收发双向 localSessionId 相同也不会冲突', () {
      final send = ConversationEntry.buildEntryId(ConversationDirection.send, 'session-1');
      final receive = ConversationEntry.buildEntryId(ConversationDirection.receive, 'session-1');
      expect(send, isNot(receive));
    });
  });

  group('ConversationEntry 序列化', () {
    ConversationEntry createEntry() {
      return ConversationEntry(
        entryId: ConversationEntry.buildEntryId(ConversationDirection.send, 'session-abc'),
        peerKey: ConversationPeer.peerKeyFor('FINGERPRINT'),
        direction: ConversationDirection.send,
        localSessionId: 'session-abc',
        kind: ConversationEntryKind.file,
        outcome: ConversationOutcome.finished,
        createdAt: DateTime.utc(2026, 11, 5, 9, 45),
        finishedAt: DateTime.utc(2026, 11, 5, 9, 46, 30),
        files: const [
          ConversationFileSummary(
            fileId: 'file-1',
            fileName: 'photo.png',
            fileType: FileType.image,
            size: 1024,
            outcome: ConversationFileOutcome.success,
            path: null,
            savedToGallery: false,
            error: null,
          ),
        ],
        text: null,
        error: null,
      );
    }

    test('Map 往返保留全部字段与 UTC 时间', () {
      final entry = createEntry();
      final decoded = ConversationEntry.fromJson(entry.toJson());

      expect(decoded, entry);
      // 持久化时间统一 UTC：往返后仍是同一 UTC 瞬间，不被转换成本地时区
      expect(decoded.createdAt.isUtc, isTrue);
      expect(decoded.createdAt, DateTime.utc(2026, 11, 5, 9, 45));
      expect(decoded.finishedAt, DateTime.utc(2026, 11, 5, 9, 46, 30));
      expect(decoded.files.single.outcome, ConversationFileOutcome.success);
    });

    test('字符串往返保留文字内容与嵌套文件摘要', () {
      final entry = createEntry();
      final decoded = ConversationEntryMapper.deserialize(entry.serialize());

      expect(decoded, entry);
      expect(decoded.files.single.fileName, 'photo.png');
    });

    test('未结束记录 finishedAt 为 null，可标记 incomplete', () {
      final pending = ConversationEntry(
        entryId: ConversationEntry.buildEntryId(ConversationDirection.receive, 'session-xyz'),
        peerKey: ConversationPeer.temporaryPeerKey(),
        direction: ConversationDirection.receive,
        localSessionId: 'session-xyz',
        kind: ConversationEntryKind.text,
        outcome: ConversationOutcome.incomplete,
        createdAt: DateTime.utc(2026, 11, 5),
        finishedAt: null,
        files: const [],
        text: '你好\n第二行', // 文字原样保留，不 trim、不丢换行
        error: null,
      );

      final decoded = ConversationEntry.fromJson(pending.toJson());
      expect(decoded, pending);
      expect(decoded.finishedAt, isNull);
      expect(decoded.text, '你好\n第二行');
    });
  });

  group('ConversationFileSummary 序列化', () {
    test('带保存结果与错误的摘要往返一致', () {
      const summary = ConversationFileSummary(
        fileId: 'file-2',
        fileName: 'report.pdf',
        fileType: FileType.pdf,
        size: 2048,
        outcome: ConversationFileOutcome.failure,
        path: '/tmp/report.pdf',
        savedToGallery: false,
        error: 'checksum mismatch',
      );

      final decoded = ConversationFileSummary.fromJson(summary.toJson());
      expect(decoded, summary);
      expect(decoded.error, 'checksum mismatch');
      expect(decoded.path, '/tmp/report.pdf');
    });

    test('未接受文件记录为 skipped 且无路径', () {
      const skipped = ConversationFileSummary(
        fileId: 'file-3',
        fileName: 'secret.apk',
        fileType: FileType.apk,
        size: 4096,
        outcome: ConversationFileOutcome.skipped,
        path: null,
        savedToGallery: false,
        error: null,
      );

      final decoded = ConversationFileSummary.fromJson(skipped.toJson());
      expect(decoded, skipped);
      expect(decoded.outcome, ConversationFileOutcome.skipped);
    });
  });
}
