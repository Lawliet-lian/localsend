import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_isolates/model/device.dart';

/// P8：会话历史持久化信封的容错解析测试（方案第 7 节门槛：坏 JSON / 截断 / 版本不符不得让启动失败）。
/// 纯字符串驱动，不依赖 SharedPreferences，直接命中 [ConversationHistoryDto.decodeFromString]。
void main() {
  ConversationPeer peer(String fp) {
    return ConversationPeer(
      peerKey: ConversationPeer.peerKeyFor(fp),
      fingerprint: fp,
      alias: 'A-$fp',
      deviceType: DeviceType.mobile,
    );
  }

  ConversationEntry entry(String id, {ConversationOutcome outcome = ConversationOutcome.finished}) {
    return ConversationEntry(
      entryId: ConversationEntry.buildEntryId(ConversationDirection.send, id),
      peerKey: ConversationPeer.peerKeyFor('AAA'),
      direction: ConversationDirection.send,
      localSessionId: id,
      kind: ConversationEntryKind.text,
      outcome: outcome,
      createdAt: DateTime.utc(2026, 11, 6),
      finishedAt: DateTime.utc(2026, 11, 6, 12),
      files: const [],
      text: 'hello $id',
      error: null,
    );
  }

  String encodeEnvelope({int? version, Object? peers = const [], Object? entries = const [], Object? truncated = const []}) {
    return jsonEncode({
      'version': version ?? conversationHistoryVersion,
      'peers': peers,
      'entries': entries,
      'truncatedEntryIds': truncated,
    });
  }

  group('ConversationHistoryDto.decodeFromString 容错', () {
    test('old entries keep unknown security and new entries retain the actual protocol', () {
      final old = entry('old').toJson()..remove('encrypted');
      final secure = entry('secure').copyWith(encrypted: true).toJson();
      final plaintext = entry('plaintext').copyWith(encrypted: false).toJson();
      final restored = ConversationHistoryDto.decodeFromString(encodeEnvelope(entries: [old, secure, plaintext]));
      expect(restored.entries.map((entry) => entry.encrypted), [null, true, false]);
    });
    test('raw 为 null：返回空信封（不抛异常）', () {
      final dto = ConversationHistoryDto.decodeFromString(null);
      expect(dto.entries, isEmpty);
      expect(dto.peers, isEmpty);
      expect(dto.version, conversationHistoryVersion);
    });

    test('坏 JSON / 写入被截断：返回空信封（不抛异常）', () {
      // 未闭合的 JSON 模拟写入被截断
      final truncated = '{"version":1,"peers":[{"peerKey":"fp:aaa"}';
      expect(ConversationHistoryDto.decodeFromString(truncated).entries, isEmpty);
      expect(ConversationHistoryDto.decodeFromString('not json at all').peers, isEmpty);
    });

    test('顶层不是对象：返回空信封', () {
      expect(ConversationHistoryDto.decodeFromString('[1,2,3]').entries, isEmpty);
      expect(ConversationHistoryDto.decodeFromString('"a string"').peers, isEmpty);
    });

    test('schema 版本不符：忽略整份旧数据（保守降级，不猜测旧格式）', () {
      final raw = encodeEnvelope(version: 999, entries: [entry('s-1').toJson()]);
      final dto = ConversationHistoryDto.decodeFromString(raw);
      expect(dto.entries, isEmpty);
      expect(dto.peers, isEmpty);
    });

    test('单条坏记录被跳过、其余有效记录保留（逐条容错）', () {
      final good = entry('s-1');
      // 第二条 entries 故意缺字段（非法结构）；第二个 peer 非对象
      final raw = encodeEnvelope(
        peers: [
          peer('AAA').toJson(),
          42, // 非法 peer
        ],
        entries: [
          good.toJson(),
          {'entryId': 'send:broken'}, // 缺方向/时间等必填字段 → fromJson 抛错
        ],
      );

      final dto = ConversationHistoryDto.decodeFromString(raw);
      // 合法的对端与记录被保留，非法的被跳过
      expect(dto.peers.length, 1);
      expect(dto.entries.length, 1);
      expect(dto.entries.single.entryId, good.entryId);
    });

    test('encode→decode 往返保真（有效数据不丢失）', () {
      final original = ConversationHistoryDto(
        version: conversationHistoryVersion,
        peers: [peer('AAA'), peer('BBB')],
        entries: [
          entry('s-1'),
          entry('s-2', outcome: ConversationOutcome.partialFailure),
        ],
        truncatedEntryIds: ['send:s-2'],
      );

      final decoded = ConversationHistoryDto.decodeFromString(jsonEncode(original.toJson()));
      expect(decoded.toJson(), original.toJson());
    });
  });

  group('ConversationHistoryDto.empty', () {
    test('空信封版本等于当前 schema 版本且集合为空', () {
      final e = ConversationHistoryDto.empty();
      expect(e.version, conversationHistoryVersion);
      expect(e.entries, isEmpty);
      expect(e.peers, isEmpty);
      expect(e.truncatedEntryIds, isEmpty);
    });
  });
}
