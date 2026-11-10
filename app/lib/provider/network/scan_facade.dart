import 'dart:async';

import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/local_ip_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// Discovers devices in stages, cheapest first: multicast announcement and
/// favorite probes right away, http-based discovery on the subnets only when
/// nothing was confirmed within 1 second.
class StartSmartScan extends AsyncGlobalAction {
  final bool revalidateKnown;
  StartSmartScan({this.revalidateKnown = false});

  /// Maximum number of interfaces to scan.
  /// If there are more interfaces, the first ones will be used or the user needs to select one.
  static const maxInterfaces = 3;

  @override
  Future<void> reduce() async {
    final favorites = ref.read(favoritesProvider);
    final settings = ref.read(settingsProvider);
    final networkInterfaces = ref.read(localIpProvider).localIps.take(maxInterfaces).toList();

    await ref
        .redux(nearbyDevicesProvider)
        .dispatchAsync(
          StartStagedScan(
            favorites: favorites,
            interfaces: networkInterfaces,
            port: settings.port,
            https: settings.https,
            grace: const Duration(seconds: 1),
            revalidateKnown: revalidateKnown,
          ),
        );
  }
}

/// 会话刷新守卫：已有扫描在途（收藏/子网）时跳过，避免快速来回切 tab 触发重叠扫描。
/// 只看“在途扫描”，不看已有设备数量——已有在线设备也允许刷新（更新地址/发现新设备）。
/// 纯函数，便于单测（与 decideReceivePresentation 同原则）。
bool shouldSkipConversationRefresh(NearbyDevicesState nearby) {
  return nearby.runningFavoriteScan || nearby.runningIps.isNotEmpty;
}

/// 切到会话页时的设备自动刷新。
///
/// 会话列表的“在线”取决于 nearbyDevicesProvider，而它只在扫描后才有设备；
/// 不主动发现就会一直显示离线。扫描期间保留旧设备，完成后移除未重新确认的 HTTP 设备。
/// 带在途扫描守卫：快速来回切 tab 时不重复触发重叠扫描。
class RefreshConversationDevices extends AsyncGlobalAction {
  @override
  Future<void> reduce() async {
    if (shouldSkipConversationRefresh(ref.read(nearbyDevicesProvider))) {
      // 已有扫描在途，跳过本次刷新
      return;
    }
    await dispatchAsync(StartSmartScan(revalidateKnown: true));
  }
}

/// HTTP based discovery on a fixed set of subnets.
class StartLegacySubnetScan extends AsyncGlobalAction {
  final List<String> subnets;

  StartLegacySubnetScan({
    required this.subnets,
  });

  @override
  Future<void> reduce() async {
    final settings = ref.read(settingsProvider);
    final port = settings.port;
    final https = settings.https;

    // send announcement in parallel
    ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());

    await Future.wait<void>([
      for (final subnet in subnets) ref.redux(nearbyDevicesProvider).dispatchAsync(StartLegacyScan(port: port, localIp: subnet, https: https)),
    ]);
  }
}
