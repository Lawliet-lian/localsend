import 'package:flutter/material.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/provider/network/scan_facade.dart';
import 'package:refena_flutter/refena_flutter.dart';

class HomePageVm {
  final PageController controller;
  final HomeTab currentTab;
  final void Function(HomeTab) changeTab;

  HomePageVm({
    required this.controller,
    required this.currentTab,
    required this.changeTab,
  });
}

final homePageControllerProvider = ReduxProvider<HomePageController, HomePageVm>(
  (ref) => HomePageController(),
);

class HomePageController extends ReduxNotifier<HomePageVm> {
  @override
  HomePageVm init() {
    return HomePageVm(
      controller: PageController(),
      currentTab: HomeTab.receive,
      changeTab: (tab) => redux.dispatch(ChangeTabAction(tab)),
    );
  }
}

class ChangeTabAction extends ReduxAction<HomePageController, HomePageVm> with GlobalActions {
  final HomeTab tab;

  ChangeTabAction(this.tab);

  @override
  HomePageVm reduce() {
    state.controller.jumpToPage(tab.index);

    // 切到会话页时自动刷新设备发现：会话列表的“在线”来自 nearbyDevicesProvider，
    // 不主动扫描会一直显示离线。fire-and-forget，不阻塞 tab 切换；刷新内部带在途扫描守卫。
    if (tab == HomeTab.conversation) {
      // ignore: discarded_futures
      global.dispatchAsync(RefreshConversationDevices());
    }

    return HomePageVm(
      controller: state.controller,
      currentTab: tab,
      changeTab: state.changeTab,
    );
  }
}
