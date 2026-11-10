import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:test/test.dart';

/// P3 显示投影测试：合并附近设备/历史/活跃收发。
/// 门槛（方案第 8 节 P3）：同指纹不同 IP 合并；同 alias 不同指纹不合并。
/// 纯函数测试，不启动 Refena container、不依赖 Rust/isolate（方案 9.1）。
void main() {
  Device device(String fingerprint, {String ip = '10.0.0.1', String alias = 'Device', DeviceType type = DeviceType.mobile}) {
    return Device(
      signalingId: null,
      ip: ip,
      version: '2.1',
      port: 53317,
      https: true,
      fingerprint: fingerprint,
      alias: alias,
      deviceModel: 'model',
      deviceType: type,
      download: false,
      channels: const [],
    );
  }

  NearbyDevicesState nearby(List<Device> devices) {
    return NearbyDevicesState(
      runningFavoriteScan: false,
      runningIps: const {},
      devices: {for (final d in devices) d.fingerprint: d},
      signalingDevices: const {},
    );
  }

  ConversationPeer historyPeer(String fingerprint, {String alias = 'History'}) {
    return ConversationPeer(
      peerKey: ConversationPeer.peerKeyFor(fingerprint),
      fingerprint: fingerprint,
      alias: alias,
      deviceType: DeviceType.desktop,
    );
  }

  ConversationEntry entry({required String peerKey, required String sessionId, required DateTime createdAt}) {
    return ConversationEntry(
      entryId: ConversationEntry.buildEntryId(ConversationDirection.send, sessionId),
      peerKey: peerKey,
      direction: ConversationDirection.send,
      localSessionId: sessionId,
      kind: ConversationEntryKind.text,
      outcome: ConversationOutcome.finished,
      createdAt: createdAt,
      finishedAt: createdAt,
      files: const [],
      text: 't',
      error: null,
    );
  }

  SendSessionState sendSession(Device target, SessionStatus status) {
    return SendSessionState(
      sessionId: 's-${target.fingerprint}',
      remoteSessionId: null,
      background: false,
      status: status,
      target: target,
      files: const {},
      hashedFileCount: 0,
      startTime: null,
      endTime: null,
      sendingTasks: null,
      errorMessage: null,
    );
  }

  ServerState serverWith(ReceiveSessionState? session) {
    return const ServerState(alias: 'me', port: 53317, https: true, session: null, web: null).copyWith(session: session);
  }

  ReceiveSessionState receiveSession(Device sender, SessionStatus status) {
    return ReceiveSessionState(
      sessionId: 'r-1',
      status: status,
      sender: sender,
      senderAlias: sender.alias,
      files: const {},
      startTime: null,
      endTime: null,
      destinationDirectory: '',
      cacheDirectory: '',
      saveToGallery: false,
      createdDirectories: const {},
    );
  }

  group('合并规则（P3 门槛）', () {
    test('收藏按指纹分组，离线且没有历史的收藏也显示', () {
      final favorites = [
        const FavoriteDevice(id: '1', fingerprint: 'aaAA', ip: '10.0.0.1', port: 53317, alias: 'Saved'),
        const FavoriteDevice(id: '2', fingerprint: 'BBBB', ip: '10.0.0.2', port: 53317, alias: 'Offline'),
      ];
      final views = buildConversationPeerViews(
        conversation: const ConversationState(),
        nearby: nearby([device('AAAA'), device('CCCC')]),
        sendSessions: const {},
        favorites: favorites,
      );
      expect(views.length, 3);
      expect(views.singleWhere((v) => v.peerKey == 'fp:aaaa').isFavorite, isTrue);
      final offline = views.singleWhere((v) => v.peerKey == 'fp:bbbb');
      expect(offline.isFavorite, isTrue);
      expect(offline.online, isFalse);
      expect(offline.alias, 'Offline');
      expect(views.singleWhere((v) => v.peerKey == 'fp:cccc').isFavorite, isFalse);
    });
    test('同指纹不同 IP 的历史与在线设备合并为一个会话，取最新 Device', () {
      final views = buildConversationPeerViews(
        conversation: ConversationState(peers: [historyPeer('AAAA')], entries: []),
        nearby: nearby([device('AAAA', ip: '10.0.0.99', alias: 'New Alias')]),
        sendSessions: const {},
      );

      expect(views.length, 1);
      final view = views.single;
      expect(view.online, true);
      expect(view.device?.ip, '10.0.0.99');
      // 在线信息优先于历史记录
      expect(view.alias, 'New Alias');
    });

    test('指纹大小写差异不分裂会话（core 大写 hex 规范化）', () {
      final views = buildConversationPeerViews(
        // 历史 peer 由小写指纹派生 fp:aaaa，在线设备上报大写 AAAA
        conversation: ConversationState(peers: [historyPeer('aaaa')], entries: []),
        nearby: nearby([device('AAAA')]),
        sendSessions: const {},
      );

      expect(views.length, 1);
      expect(views.single.peerKey, 'fp:aaaa');
    });

    test('同 alias 不同指纹不合并，是两个独立会话', () {
      final views = buildConversationPeerViews(
        conversation: const ConversationState(),
        nearby: nearby([
          device('FP-1', ip: '10.0.0.1', alias: '同名设备'),
          device('FP-2', ip: '10.0.0.2', alias: '同名设备'),
        ]),
        sendSessions: const {},
      );

      expect(views.length, 2);
      expect(views.map((v) => v.peerKey).toSet(), {'fp:fp-1', 'fp:fp-2'});
    });
  });

  group('在线/离线与摘要', () {
    test('只在线无历史的设备进入列表（空会话详情可发送）', () {
      final views = buildConversationPeerViews(
        conversation: const ConversationState(),
        nearby: nearby([device('FP-1')]),
        sendSessions: const {},
      );

      expect(views.single.online, true);
      expect(views.single.entryCount, 0);
      expect(views.single.lastEntry, isNull);
    });

    test('只有历史、当前未发现的设备保留为离线（device 为 null，UI 应禁用发送）', () {
      final views = buildConversationPeerViews(
        conversation: ConversationState(
          peers: [historyPeer('FP-9', alias: 'Old Name')],
          entries: [entry(peerKey: 'fp:fp-9', sessionId: 's-1', createdAt: DateTime.utc(2026, 11, 1))],
        ),
        nearby: nearby([]),
        sendSessions: const {},
      );

      expect(views.single.online, false);
      expect(views.single.device, isNull);
      expect(views.single.alias, 'Old Name');
      expect(views.single.entryCount, 1);
    });

    test('lastEntry 取 createdAt 最新的一条', () {
      final views = buildConversationPeerViews(
        conversation: ConversationState(
          peers: [historyPeer('FP-1')],
          entries: [
            entry(peerKey: 'fp:fp-1', sessionId: 'old', createdAt: DateTime.utc(2026, 1, 1)),
            entry(peerKey: 'fp:fp-1', sessionId: 'new', createdAt: DateTime.utc(2026, 6, 1)),
            entry(peerKey: 'fp:fp-1', sessionId: 'mid', createdAt: DateTime.utc(2026, 3, 1)),
          ],
        ),
        nearby: nearby([]),
        sendSessions: const {},
      );

      expect(views.single.lastEntry?.localSessionId, 'new');
      expect(views.single.entryCount, 3);
    });
  });

  group('活跃收发合并', () {
    test('活跃发送（waiting/sending）标记 hasActiveSend；已结束 session 不标记', () {
      final d1 = device('FP-1');
      final d2 = device('FP-2');
      final views = buildConversationPeerViews(
        conversation: const ConversationState(),
        nearby: nearby([d1, d2]),
        sendSessions: {
          's1': sendSession(d1, SessionStatus.sending),
          's2': sendSession(d2, SessionStatus.finished),
        },
      );

      expect(views.firstWhere((v) => v.peerKey == 'fp:fp-1').hasActiveSend, true);
      expect(views.firstWhere((v) => v.peerKey == 'fp:fp-2').hasActiveSend, false);
    });

    test('活跃接收 session 标记来源设备 hasActiveReceive，其他设备不受影响', () {
      final sender = device('FP-SENDER');
      final views = buildConversationPeerViews(
        conversation: const ConversationState(),
        nearby: nearby([sender, device('FP-OTHER')]),
        sendSessions: const {},
        serverState: serverWith(receiveSession(sender, SessionStatus.waiting)),
      );

      expect(views.firstWhere((v) => v.peerKey == 'fp:fp-sender').hasActiveReceive, true);
      expect(views.firstWhere((v) => v.peerKey == 'fp:fp-other').hasActiveReceive, false);
    });

    test('已结束的接收 session 不标记', () {
      final sender = device('FP-SENDER');
      final views = buildConversationPeerViews(
        conversation: const ConversationState(),
        nearby: nearby([sender]),
        sendSessions: const {},
        serverState: serverWith(receiveSession(sender, SessionStatus.canceledByReceiver)),
      );

      expect(views.single.hasActiveReceive, false);
    });
  });

  group('排序', () {
    test('在线优先，其后按最后记录时间倒序', () {
      final views = buildConversationPeerViews(
        conversation: ConversationState(
          peers: [historyPeer('FP-OFF'), historyPeer('FP-ONLINE')],
          entries: [
            entry(peerKey: 'fp:fp-off', sessionId: 'a', createdAt: DateTime.utc(2026, 10, 1)),
            entry(peerKey: 'fp:fp-online', sessionId: 'b', createdAt: DateTime.utc(2026, 1, 1)),
          ],
        ),
        // FP-ONLINE 在线但记录更旧；FP-OFF 离线但记录更新 → 在线优先
        nearby: nearby([device('FP-ONLINE')]),
        sendSessions: const {},
      );

      expect(views.map((v) => v.peerKey), ['fp:fp-online', 'fp:fp-off']);
    });
  });
}
