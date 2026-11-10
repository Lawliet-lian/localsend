import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/config/init.dart';
import 'package:localsend_app/config/theme.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/quick_save_mode.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/pages/tabs/conversation_tab.dart';
import 'package:localsend_app/pages/tabs/receive_tab.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart';
import 'package:localsend_app/pages/tabs/settings_tab.dart';
import 'package:localsend_app/provider/conversation_ui_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/cross_file_converters.dart';
import 'package:localsend_app/widget/conversation/pane_divider.dart';
import 'package:localsend_app/widget/responsive_builder.dart';
import 'package:refena_flutter/refena_flutter.dart';

enum HomeTab {
  receive(Icons.wifi),
  send(Icons.send),
  settings(Icons.settings),
  // 会话入口追加在末尾：不改变原有 tab 的 index（方案 6.1）
  conversation(Icons.forum)
  ;

  const HomeTab(this.icon);

  final IconData icon;

  String get label {
    switch (this) {
      case HomeTab.receive:
        return t.receiveTab.title;
      case HomeTab.send:
        return t.sendTab.title;
      case HomeTab.settings:
        return t.settingsTab.title;
      case HomeTab.conversation:
        return t.conversation.title;
    }
  }
}

class HomePage extends StatefulWidget {
  final HomeTab initialTab;

  /// It is important for the initializing step
  /// because the first init clears the cache
  final bool appStart;

  const HomePage({
    required this.initialTab,
    required this.appStart,
    super.key,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with Refena {
  bool _dragAndDropIndicator = false;
  double _navigationWidth = 220;
  double _listWidth = 260;
  bool _navigationCollapsed = false;
  bool _listCollapsed = false;

  /// 启动时是否仍待自动选中「列表第一个设备」。
  /// 仅 appStart 且横屏/桌面生效；竖屏或用户已手动选中后置 false，避免覆盖用户操作。
  bool _autoSelectFirstPending = false;

  @override
  void initState() {
    super.initState();

    ensureRef((ref) async {
      final persistence = ref.read(persistenceProvider);
      setState(() {
        _navigationWidth = persistence.getConversationNavigationWidth();
        _listWidth = persistence.getConversationListWidth();
        _navigationCollapsed = persistence.getConversationNavigationCollapsed();
        _listCollapsed = persistence.getConversationListCollapsed();
      });
      // 启动默认进入会话 tab，不再恢复上次停留的 tab 与上次会话设备（后者可能已不存在）。
      // 三栏宽度/折叠状态仍按上次关闭时的持久化值恢复（拖拽结束即落盘）。
      final initialTab = widget.appStart ? HomeTab.conversation : widget.initialTab;
      if (widget.appStart) {
        _autoSelectFirstPending = true;
        // 首帧后按当前横竖屏决定是否自动打开第一个设备；竖屏只停留在会话列表。
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoSelectFirst());
      }
      ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(initialTab));
      await postInit(context, ref, widget.appStart);
      if (widget.appStart && mounted && ref.read(persistenceProvider).needsReceiveConfirmationMigration()) {
        final previous = ref.read(persistenceProvider).getQuickSave();
        var selected = previous;
        final mode = await showDialog<QuickSaveMode>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: Text(t.settingsTab.receive.reviewReceiveSettings),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(t.settingsTab.receive.reviewReceiveSettingsHint),
                    RadioGroup<QuickSaveMode>(
                      groupValue: selected,
                      onChanged: (value) => setDialogState(() => selected = value ?? selected),
                      child: Column(
                        children: [
                          RadioListTile<QuickSaveMode>(value: QuickSaveMode.off, title: Text(t.settingsTab.receive.confirmEveryRequest)),
                          RadioListTile<QuickSaveMode>(value: QuickSaveMode.paired, title: Text(t.settingsTab.receive.acceptFavorites)),
                          RadioListTile<QuickSaveMode>(value: QuickSaveMode.on, title: Text(t.settingsTab.receive.acceptAllDevices)),
                        ],
                      ),
                    ),
                    Text(t.settingsTab.receive.receiveConfirmationHint),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(t.settingsTab.receive.chooseLater)),
                TextButton(onPressed: () => Navigator.pop(dialogContext, selected), child: Text(t.general.confirm)),
              ],
            ),
          ),
        );
        if (mode != null) await ref.notifier(settingsProvider).setReceiveConfirmation(mode);
      }
    });
  }

  /// 启动自动选中列表第一个设备（桌面/横屏）。
  /// 竖屏（高 > 宽）只停留在会话列表；列表暂空时保持 pending，等设备出现由 build 的 listener 再触发。
  /// 用户已手动选中设备时不再覆盖。
  void _maybeAutoSelectFirst() {
    if (!_autoSelectFirstPending || !mounted) return;
    final size = MediaQuery.sizeOf(context);
    if (size.height > size.width) {
      _autoSelectFirstPending = false;
      return;
    }
    if (ref.read(conversationUiProvider).selectedPeerKey != null) {
      _autoSelectFirstPending = false;
      return;
    }
    final views = ref.read(conversationPeerViewsProvider);
    if (views.isEmpty) return;
    _autoSelectFirstPending = false;
    ref.notifier(conversationUiProvider).selectPeer(views.first.peerKey);
  }

  @override
  Widget build(BuildContext context) {
    Translations.of(context); // rebuild on locale change
    final vm = context.watch(homePageControllerProvider);
    final conversationUi = context.watch(conversationUiProvider);
    final conversationViews = context.watch(
      conversationPeerViewsProvider,
      listener: (prev, next) {
        // 启动时列表可能先空后发现：首个设备出现时补选一次。
        if (_autoSelectFirstPending) _maybeAutoSelectFirst();
      },
    );

    void changeTab(HomeTab tab) {
      vm.changeTab(tab);
      unawaited(ref.read(persistenceProvider).setLastHomeTab(tab.name));
    }

    void setNavigationCollapsed(bool value) {
      setState(() => _navigationCollapsed = value);
      unawaited(ref.read(persistenceProvider).setConversationNavigationCollapsed(value));
    }

    return DropTarget(
      enable: vm.currentTab != HomeTab.conversation,
      onDragEntered: (_) {
        setState(() {
          _dragAndDropIndicator = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _dragAndDropIndicator = false;
        });
      },
      onDragDone: (event) async {
        // the drop may contain a mix of files and directories
        final droppedDirectories = event.files.where((file) => Directory(file.path).existsSync()).toList();
        final droppedFiles = event.files.where((file) => !Directory(file.path).existsSync()).toList();

        for (final directory in droppedDirectories) {
          await ref.redux(selectedSendingFilesProvider).dispatchAsync(AddDirectoryAction(directory.path));
        }

        if (droppedFiles.isNotEmpty) {
          await ref
              .redux(selectedSendingFilesProvider)
              .dispatchAsync(
                AddFilesAction(
                  files: droppedFiles,
                  converter: CrossFileConverters.convertXFile,
                ),
              );
        }
        changeTab(HomeTab.send);
      },
      child: ResponsiveBuilder(
        builder: (sizingInformation) {
          final adjustable = sizingInformation.isDesktop && vm.currentTab == HomeTab.conversation && MediaQuery.sizeOf(context).width >= 808;
          final maxNavigationWidth = (MediaQuery.sizeOf(context).width - 628).clamp(72.0, 360.0);
          final navigationWidth = _navigationWidth.clamp(72.0, maxNavigationWidth);
          final compactNavigation = adjustable && navigationWidth < 180;
          return Scaffold(
            body: Row(
              children: [
                if (adjustable && _navigationCollapsed)
                  Align(
                    alignment: Alignment.topCenter,
                    child: IconButton(
                      tooltip: t.conversation.expand,
                      onPressed: () => setNavigationCollapsed(false),
                      icon: const Icon(Icons.menu),
                    ),
                  )
                else if (!sizingInformation.isMobile)
                  SizedBox(
                    width: adjustable ? navigationWidth : (sizingInformation.isDesktop ? 256 : 72),
                    child: ColoredBox(
                      color: Theme.of(context).cardColorWithElevation,
                      child: Column(
                        children: [
                          if (sizingInformation.isDesktop) ...[
                            const SizedBox(height: 20),
                            Text(compactNavigation ? 'LC' : 'LocalChat', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                            if (adjustable)
                              IconButton(
                                tooltip: t.conversation.collapse,
                                onPressed: () => setNavigationCollapsed(true),
                                icon: const Icon(Icons.first_page),
                              )
                            else
                              const SizedBox(height: 20),
                          ],
                          Expanded(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: NavigationRail(
                                selectedIndex: vm.currentTab.index,
                                onDestinationSelected: (index) => changeTab(HomeTab.values[index]),
                                extended: sizingInformation.isDesktop && !compactNavigation,
                                minExtendedWidth: 180,
                                backgroundColor: Theme.of(context).cardColorWithElevation,
                                destinations: HomeTab.values
                                    .map((tab) => NavigationRailDestination(icon: Icon(tab.icon), label: Text(tab.label)))
                                    .toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (adjustable && !_navigationCollapsed)
                  PaneDivider(
                    onDrag: (delta) => setState(() => _navigationWidth = (navigationWidth + delta).clamp(72.0, maxNavigationWidth)),
                    onDragEnd: () => ref.read(persistenceProvider).setConversationNavigationWidth(_navigationWidth),
                  ),
                Expanded(
                  child: SafeArea(
                    left: sizingInformation.isMobile,
                    child: Stack(
                      children: [
                        PageView(
                          controller: vm.controller,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            const ReceiveTab(),
                            const SendTab(),
                            const SettingsTab(),
                            ConversationTab(
                              dropEnabled: vm.currentTab == HomeTab.conversation,
                              listWidth: _listWidth,
                              listCollapsed: _listCollapsed,
                              onListCollapsed: (value) {
                                setState(() => _listCollapsed = value);
                                unawaited(ref.read(persistenceProvider).setConversationListCollapsed(value));
                              },
                              onListWidthChanged: (value) => setState(() => _listWidth = value),
                              onListResizeEnd: () => ref.read(persistenceProvider).setConversationListWidth(_listWidth),
                            ),
                          ],
                        ),
                        if (_dragAndDropIndicator)
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.file_download, size: 128),
                                const SizedBox(height: 30),
                                Text(t.sendTab.placeItems, style: Theme.of(context).textTheme.titleLarge),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar:
                sizingInformation.isMobile &&
                    !(defaultTargetPlatform == TargetPlatform.android &&
                        vm.currentTab == HomeTab.conversation &&
                        conversationUi.showDetailOnMobile &&
                        conversationViews.any((view) => view.peerKey == conversationUi.selectedPeerKey))
                ? NavigationBar(
                    selectedIndex: vm.currentTab.index,
                    onDestinationSelected: (index) => changeTab(HomeTab.values[index]),
                    destinations: HomeTab.values.map((tab) {
                      return NavigationDestination(icon: Icon(tab.icon), label: tab.label);
                    }).toList(),
                  )
                : null,
          );
        },
      ),
    );
  }
}
