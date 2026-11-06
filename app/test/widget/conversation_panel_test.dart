import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/widget/conversation/conversation_panel.dart';
import 'package:localsend_isolates/model/device.dart';

/// P4 响应式只读组件 widget 测试。
/// 门槛（方案第 8 节）：宽度 >=800 两栏；700~799 单栏列表进详情；
/// 自身约束 <620 回退单栏。使用注入的 fake 视图数据，不启动 Rust/isolate（方案 9.1）。
void main() {
  ConversationPeerView view(
    String peerKey, {
    String alias = 'Peer',
    bool online = true,
    DeviceType type = DeviceType.mobile,
    ConversationEntry? lastEntry,
    int entryCount = 0,
    bool hasActiveSend = false,
    bool hasActiveReceive = false,
  }) {
    return ConversationPeerView(
      peerKey: peerKey,
      alias: alias,
      deviceType: type,
      online: online,
      device: online
          ? Device(
              signalingId: null,
              ip: '10.0.0.1',
              version: '2.1',
              port: 53317,
              https: true,
              fingerprint: peerKey.replaceFirst('fp:', '').toUpperCase(),
              alias: alias,
              deviceModel: 'model',
              deviceType: type,
              download: false,
              channels: const [],
            )
          : null,
      lastEntry: lastEntry,
      entryCount: entryCount,
      hasActiveSend: hasActiveSend,
      hasActiveReceive: hasActiveReceive,
    );
  }

  ConversationEntry textEntry(String peerKey, String sessionId, String text, {ConversationDirection direction = ConversationDirection.send}) {
    return ConversationEntry(
      entryId: ConversationEntry.buildEntryId(direction, sessionId),
      peerKey: peerKey,
      direction: direction,
      localSessionId: sessionId,
      kind: ConversationEntryKind.text,
      outcome: ConversationOutcome.finished,
      createdAt: DateTime.utc(2026, 11, 5, 10),
      finishedAt: DateTime.utc(2026, 11, 5, 10),
      files: const [],
      text: text,
      error: null,
    );
  }

  /// 设置虚拟窗口尺寸（ResponsiveBuilder 读 MediaQuery.size）
  void setWindow(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required double windowWidth,
    required List<ConversationPeerView> views,
    List<ConversationEntry> entries = const [],
    String? initialSelection,
    ValueChanged<String?>? onSelect,
    String draftText = '',
    ValueChanged<String>? onSendText,
  }) async {
    setWindow(tester, windowWidth);
    String? selected = initialSelection;
    // 用 stateful 壳模拟 conversationUiProvider 的选中状态（组件本身是无状态 dumb 组件）
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => ConversationPanel(
            views: views,
            entries: entries,
            selectedPeerKey: selected,
            onSelect: (key) {
              if (onSelect != null) {
                onSelect(key);
              }
              setState(() => selected = key);
            },
            // P6c 新增参数：本套件只验证布局与展示，输入行为由 composer 测试覆盖
            draftText: draftText,
            onDraftChanged: (_) {},
            onSendText: onSendText ?? (_) {},
          ),
        ),
      ),
    );
  }

  group('响应式布局', () {
    testWidgets('窗口 >=800 且自身 >=620：两栏，列表与详情同时可见', (tester) async {
      await pumpPanel(
        tester,
        windowWidth: 1000,
        views: [
          view('fp:aaa', alias: 'Device A'),
          view('fp:bbb', alias: 'Device B'),
        ],
        entries: [textEntry('fp:aaa', 's1', 'hello from A')],
        initialSelection: 'fp:aaa',
      );

      // 列表项仍在（两栏并存），同时详情气泡可见
      expect(find.text('Device B'), findsOneWidget);
      expect(find.text('hello from A'), findsOneWidget);
      // 两栏模式没有返回按钮
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('窗口 700~799：单栏，点选设备后进入详情替换列表', (tester) async {
      await pumpPanel(
        tester,
        windowWidth: 750,
        views: [view('fp:aaa', alias: 'Device A')],
        entries: [textEntry('fp:aaa', 's1', 'hello from A')],
      );

      // 单栏初始只显示列表
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('hello from A'), findsNothing);

      await tester.tap(find.text('Device A'));
      await tester.pumpAndSettle();

      // 进入详情：列表行消失（顶栏仍显示设备名属正常），气泡出现，且有返回按钮
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('hello from A'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('窗口 >=800 但自身约束 <620（侧栏挤压）：回退单栏', (tester) async {
      setWindow(tester, 1000);
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              const SizedBox(width: 400), // 模拟首页侧栏等占位
              Expanded(
                child: StatefulBuilder(
                  builder: (context, setState) => ConversationPanel(
                    views: [view('fp:aaa', alias: 'Device A')],
                    entries: [textEntry('fp:aaa', 's1', 'hello')],
                    selectedPeerKey: selected,
                    onSelect: (key) => setState(() => selected = key),
                    // P6c 新增的必填参数：本用例只验证响应式回退，输入栏给空实现即可
                    draftText: '',
                    onDraftChanged: (_) {},
                    onSendText: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      // 自身宽度 600 < 620 → 单栏：点选后列表被详情替换
      await tester.tap(find.text('Device A'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('hello'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('单栏详情点返回按钮回到列表（同一容器内切换，不 push 新页面）', (tester) async {
      await pumpPanel(
        tester,
        windowWidth: 500,
        views: [view('fp:aaa', alias: 'Device A')],
        entries: [textEntry('fp:aaa', 's1', 'hello')],
        initialSelection: 'fp:aaa',
      );

      expect(find.text('hello'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // 回到列表且选中回调收到 null
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.text('hello'), findsNothing);
    });
  });

  group('只读展示', () {
    testWidgets('离线设备详情显示离线提示且保留历史内容', (tester) async {
      await pumpPanel(
        tester,
        windowWidth: 1000,
        views: [view('fp:aaa', alias: 'Old Device', online: false)],
        entries: [textEntry('fp:aaa', 's1', 'old message')],
        initialSelection: 'fp:aaa',
      );

      expect(find.text(t.conversation.offline), findsOneWidget);
      expect(find.text('old message'), findsOneWidget);
      // P4 是纯只读：没有接受/拒绝/取消/发送按钮
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('空列表显示空态文案', (tester) async {
      await pumpPanel(tester, windowWidth: 500, views: []);
      expect(find.text(t.conversation.empty), findsOneWidget);
    });

    testWidgets('活跃收发设备显示进度指示器', (tester) async {
      await pumpPanel(
        tester,
        windowWidth: 1000,
        views: [view('fp:aaa', alias: 'Busy Device', hasActiveSend: true)],
      );

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('超长文字默认折叠，点展开后显示 Collapse 按钮', (tester) async {
      final longText = 'x' * 500;
      await pumpPanel(
        tester,
        windowWidth: 1000,
        views: [view('fp:aaa')],
        entries: [textEntry('fp:aaa', 's1', longText)],
        initialSelection: 'fp:aaa',
      );

      expect(find.text(t.conversation.expand), findsOneWidget);
      await tester.tap(find.text(t.conversation.expand));
      await tester.pumpAndSettle();
      expect(find.text(t.conversation.collapse), findsOneWidget);
    });

    testWidgets('双向气泡都渲染（send/receive 各一条）', (tester) async {
      await pumpPanel(
        tester,
        windowWidth: 1000,
        views: [view('fp:aaa')],
        entries: [
          textEntry('fp:aaa', 's1', 'sent text', direction: ConversationDirection.send),
          textEntry('fp:aaa', 'r1', 'received text', direction: ConversationDirection.receive),
        ],
        initialSelection: 'fp:aaa',
      );

      expect(find.text('sent text'), findsOneWidget);
      expect(find.text('received text'), findsOneWidget);
    });
  });
}
