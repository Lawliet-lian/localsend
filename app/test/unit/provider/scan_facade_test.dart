import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/state/nearby_devices_state.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';

/// 会话页设备自动刷新的守卫合同测试。
/// 切到会话页会触发 RefreshConversationDevices（复用 StartSmartScan）；
/// 守卫只关心"是否有扫描在途"，避免快速来回切 tab 造成重叠扫描，
/// 不关心已有设备数量（已有在线设备也要能刷新地址/发现新设备）。
void main() {
  group('shouldSkipConversationRefresh', () {
    NearbyDevicesState state({bool runningFavoriteScan = false, Set<String> runningIps = const {}}) {
      return NearbyDevicesState(
        runningFavoriteScan: runningFavoriteScan,
        runningIps: runningIps,
        devices: const {},
        signalingDevices: const {},
      );
    }

    test('testIdleAllowsRefresh', () {
      // 无扫描在途：允许刷新（即使 devices 为空——这正是会话页一直离线的场景）
      expect(shouldSkipConversationRefresh(state()), false);
    });

    test('testRunningFavoriteScanSkipsRefresh', () {
      // 收藏/多播阶段扫描在途：跳过，避免重叠
      expect(shouldSkipConversationRefresh(state(runningFavoriteScan: true)), true);
    });

    test('testRunningSubnetScanSkipsRefresh', () {
      // 子网 HTTP 扫描在途：同样跳过
      expect(shouldSkipConversationRefresh(state(runningIps: {'192.168.1.10'})), true);
    });
  });
}
