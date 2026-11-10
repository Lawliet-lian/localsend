import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/server/server_state.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 会话列表中一个设备条目的轻量视图（方案 5.1 显示投影层）。
///
/// 视图是只读投影，不拥有任何状态：传输仍由 sendProvider/serverProvider/fileTransferProvider
/// 负责（第 4 节不变量 1：会话展示状态不是传输状态，本层无任何取消能力）。
class ConversationPeerView {
  final String peerKey;

  /// 展示名称：在线时取最近发现的 Device.alias，否则取历史记录中的 alias。
  final String alias;

  final DeviceType deviceType;

  /// 是否被当前发现（多播/信令）。语义是"在线/未发现"，不是"已连接"（不变量 8）。
  /// 离线设备仍可查看历史，UI 需据此禁用发送（方案 6.2）。
  final bool online;
  final bool isFavorite;

  /// 在线时的最新可用 Device（发送时取最新地址，保留 IPv6 scope，不变量 5）；离线为 null。
  final Device? device;

  /// 最后一条会话记录（用于列表摘要），无历史为 null。
  final ConversationEntry? lastEntry;

  /// 该设备的记录条数。
  final int entryCount;

  /// 是否存在对该设备的活跃发送 session（waiting/sending）。
  final bool hasActiveSend;

  /// 当前接收 session 是否来自该设备（接收端同时只有一个活跃 session）。
  final bool hasActiveReceive;

  const ConversationPeerView({
    required this.peerKey,
    required this.alias,
    required this.deviceType,
    required this.online,
    this.isFavorite = false,
    required this.device,
    required this.lastEntry,
    required this.entryCount,
    required this.hasActiveSend,
    required this.hasActiveReceive,
  });
}

/// 传输 session 是否处于活跃（未结束）状态。
/// waiting（等对方决定）与 sending（传输中）之外都是终态（共享 SessionStatus 语义，不修改该枚举）。
bool _isLiveSession(SessionStatus status) {
  return status == SessionStatus.waiting || status == SessionStatus.sending;
}

/// 纯投影函数：合并会话摘要层、附近设备、活跃收发为视图列表。
///
/// 独立成函数是为了可测试性（方案 9.1：不启动实际 Rust 服务即可覆盖合并规则）。
/// 合并合同：
/// - 设备身份以 peerKey（指纹派生稳定键）为准：同指纹不同 IP 合并为一个会话；
/// - 同 alias 不同指纹是两个不同会话，绝不合并（不变量 4/5）；
/// - 缺少可信身份的临时会话（tmp:）只与自身匹配。
List<ConversationPeerView> buildConversationPeerViews({
  required ConversationState conversation,
  required NearbyDevicesState nearby,
  required Map<String, SendSessionState> sendSessions,
  List<FavoriteDevice> favorites = const [],
  ServerState? serverState,
}) {
  // 在线设备按 peerKey 建索引：指纹统一小写规范化，避免大小写差异分裂会话。
  final deviceByPeerKey = <String, Device>{};
  for (final device in nearby.allDevices.values) {
    deviceByPeerKey[ConversationPeer.peerKeyFor(device.fingerprint)] = device;
  }

  // 历史 peer 索引
  final peerByPeerKey = {for (final p in conversation.peers) p.peerKey: p};
  final favoriteByPeerKey = <String, FavoriteDevice>{
    for (final favorite in favorites)
      if (favorite.fingerprint.trim().isNotEmpty) ConversationPeer.peerKeyFor(favorite.fingerprint): favorite,
  };

  // entries 按 peer 聚合：最后一条（createdAt 最大）+ 条数
  final lastEntryByPeer = <String, ConversationEntry>{};
  final countByPeer = <String, int>{};
  for (final entry in conversation.entries) {
    countByPeer[entry.peerKey] = (countByPeer[entry.peerKey] ?? 0) + 1;
    final current = lastEntryByPeer[entry.peerKey];
    if (current == null || entry.createdAt.isAfter(current.createdAt)) {
      lastEntryByPeer[entry.peerKey] = entry;
    }
  }

  // 活跃发送 session 按目标设备 peerKey 聚合
  final activeSendPeerKeys = <String>{};
  for (final session in sendSessions.values) {
    if (_isLiveSession(session.status)) {
      activeSendPeerKeys.add(ConversationPeer.peerKeyFor(session.target.fingerprint));
    }
  }

  // 当前接收 session 的对端
  String? activeReceivePeerKey;
  final receiveSession = serverState?.session;
  if (receiveSession != null && _isLiveSession(receiveSession.status)) {
    activeReceivePeerKey = ConversationPeer.peerKeyFor(receiveSession.sender.fingerprint);
  }

  // 候选集合：所有有历史的 peer + 所有当前发现的设备。
  // 只在线无历史的设备也进入列表（首次会话为空详情，方案第 2 节核心交付 1）。
  final peerKeys = <String>{...peerByPeerKey.keys, ...deviceByPeerKey.keys, ...favoriteByPeerKey.keys};

  final views = <ConversationPeerView>[];
  for (final peerKey in peerKeys) {
    final device = deviceByPeerKey[peerKey];
    final historyPeer = peerByPeerKey[peerKey];
    final favorite = favoriteByPeerKey[peerKey];

    // 在线信息优先于历史记录：alias/deviceType 取最近一次观察结果
    final alias = favorite?.customAlias == true ? favorite!.alias : device?.alias ?? historyPeer?.alias ?? favorite?.alias ?? '?';
    final deviceType = device?.deviceType ?? historyPeer?.deviceType ?? DeviceType.mobile;

    views.add(
      ConversationPeerView(
        peerKey: peerKey,
        alias: alias,
        deviceType: deviceType,
        online: device != null,
        isFavorite: favorite != null,
        device: device,
        lastEntry: lastEntryByPeer[peerKey],
        entryCount: countByPeer[peerKey] ?? 0,
        hasActiveSend: activeSendPeerKeys.contains(peerKey),
        hasActiveReceive: activeReceivePeerKey == peerKey,
      ),
    );
  }

  // 稳定排序：在线优先，其次按最后记录时间倒序；两者皆无的按名称。
  // 最终列表分组/渲染顺序由 P4 决定，这里只提供确定性基线。
  views.sort((a, b) {
    if (a.online != b.online) {
      return a.online ? -1 : 1;
    }
    final aTime = a.lastEntry?.createdAt;
    final bTime = b.lastEntry?.createdAt;
    if (aTime != null && bTime != null) {
      final byTime = bTime.compareTo(aTime);
      if (byTime != 0) {
        return byTime;
      }
    } else if (aTime != null) {
      return -1;
    } else if (bTime != null) {
      return 1;
    }
    return a.alias.compareTo(b.alias);
  });

  return views;
}

/// 会话视图投影 provider：为 P4 组件提供合并后的轻量只读视图。
///
/// 注意：本 provider 只 watch 不写；任何交互动作仍归属原有传输 provider，
/// 显示投影不新增并发能力，也不改变任何传输行为。
final conversationPeerViewsProvider = ViewProvider((ref) {
  final conversation = ref.watch(conversationProvider);
  final nearby = ref.watch(nearbyDevicesProvider);
  final sendSessions = ref.watch(sendProvider);
  final serverState = ref.watch(serverProvider);
  final favorites = ref.watch(favoritesProvider);

  return buildConversationPeerViews(
    conversation: conversation,
    nearby: nearby,
    sendSessions: sendSessions,
    serverState: serverState,
    favorites: favorites,
  );
});
