import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/tabs/conversation_tab.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/conversation_ui_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// P5 会话入口接线测试 + P6c 文字发送接线测试。
/// 用 overrideWithBuilder 注入 fake 投影结果，不启动 Rust/isolate（方案 9.1）；
/// 发送路径用 fake SendNotifier 替换（startSession 真实实现依赖 Rust http）；
/// conversationProvider 与 conversationUiProvider 使用真实实例（纯内存、无持久化依赖）。

/// 替换真实发送：只记录调用参数，不碰网络
/// （验证 presentation=conversation 接线与原文编码，不验证传输本身）
class _RecordingSendNotifier extends SendNotifier {
  final calls = <({Device target, List<CrossFile> files, bool background, TransferPresentation presentation})>[];

  @override
  Future<void> startSession({
    required Device target,
    required List<CrossFile> files,
    required bool background,
    TransferPresentation presentation = TransferPresentation.legacy,
  }) async {
    calls.add((target: target, files: files, background: background, presentation: presentation));
  }
}

void main() {
  ConversationPeerView fakeView(
    String peerKey, {
    String alias = 'Fake Peer',
    bool online = true,
    Device? device,
  }) {
    return ConversationPeerView(
      peerKey: peerKey,
      alias: alias,
      deviceType: DeviceType.desktop,
      online: online,
      device: device,
      lastEntry: ConversationEntry(
        entryId: ConversationEntry.buildEntryId(ConversationDirection.send, 's-1'),
        peerKey: peerKey,
        direction: ConversationDirection.send,
        localSessionId: 's-1',
        kind: ConversationEntryKind.text,
        outcome: ConversationOutcome.finished,
        createdAt: DateTime.utc(2026, 11, 5),
        finishedAt: DateTime.utc(2026, 11, 5),
        files: const [],
        text: 'injected message',
        error: null,
      ),
      entryCount: 1,
      hasActiveSend: false,
      hasActiveReceive: false,
    );
  }

  void setWindow(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpTab(
    WidgetTester tester, {
    required double width,
    required List<ConversationPeerView> views,
    required void Function(Ref) onRef,
    List<ProviderOverride> overrides = const [],
  }) async {
    setWindow(tester, width);
    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          conversationPeerViewsProvider.overrideWithBuilder((_) => views),
          ...overrides,
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              // 把 tab 所在容器的 ref 交给测试，用于向真实 conversationProvider 播种记录
              onRef(context.ref);
              return const ConversationTab();
            },
          ),
        ),
      ),
    );
  }

  /// 向真实（未 override 的）conversationProvider 播种一条文字记录：
  /// 详情气泡区渲染的是 entries，不是 view.lastEntry。
  void seedEntry(Ref ref, String peerKey, String text) {
    ref
        .redux(conversationProvider)
        .dispatch(
          EnsureTransferEntryAction(
            peer: ConversationPeer(
              peerKey: peerKey,
              fingerprint: peerKey.replaceFirst('fp:', '').toUpperCase(),
              alias: 'Real Device',
              deviceType: DeviceType.desktop,
            ),
            direction: ConversationDirection.send,
            localSessionId: 's-1',
            kind: ConversationEntryKind.text,
            files: const [],
            text: text,
          ),
        );
  }

  testWidgets('宽屏两栏：注入的真实投影数据渲染列表，未选中时右列提示选择设备', (tester) async {
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device')],
      onRef: (_) {},
    );

    expect(find.text('Real Device'), findsOneWidget);
    expect(find.text(t.conversation.selectDevice), findsOneWidget);
    // 生产接线不得出现任何 fake 在线/假消息之外的占位（气泡未选中不渲染）
    expect(find.text('injected message'), findsNothing);
  });

  testWidgets('宽屏点选设备：conversationUiProvider 选中后右列渲染气泡', (tester) async {
    late Ref ref;
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device')],
      onRef: (r) => ref = r,
    );
    seedEntry(ref, 'fp:aaa', 'injected message');
    await tester.pump();

    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();

    // 两栏并存：列表项 + 详情顶栏共 2 处设备名，右列出现详情气泡
    expect(find.text('Real Device'), findsNWidgets(2));
    expect(find.text('injected message'), findsOneWidget);
  });

  testWidgets('窄屏：点选进入详情，返回按钮回到列表（backToList 接线）', (tester) async {
    late Ref ref;
    await pumpTab(
      tester,
      width: 500,
      views: [fakeView('fp:aaa', alias: 'Real Device')],
      onRef: (r) => ref = r,
    );
    seedEntry(ref, 'fp:aaa', 'injected message');
    await tester.pump();

    // 初始单栏列表
    expect(find.byType(ListTile), findsOneWidget);

    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();

    // 进入详情（selectPeer 置 showDetailOnMobile）
    expect(find.byType(ListTile), findsNothing);
    expect(find.text('injected message'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // 返回列表（backToList 只收起详情；选中高亮保留在 provider 内）
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.text('injected message'), findsNothing);
  });

  testWidgets('空投影显示空态文案（无设备无历史）', (tester) async {
    await pumpTab(tester, width: 500, views: [], onRef: (_) {});
    expect(find.text(t.conversation.empty), findsOneWidget);
  });

  // ---- P6c 文字发送接线 ----

  Device onlineDevice() {
    return Device(
      signalingId: null,
      ip: '10.0.0.1',
      version: '2.1',
      port: 53317,
      https: true,
      fingerprint: 'AA:BB',
      alias: 'Real Device',
      deviceModel: 'model',
      deviceType: DeviceType.desktop,
      download: false,
      channels: const [],
    );
  }

  testWidgets('P6c 文字发送：走 startSession(conversation)，原文编码，发送后清草稿', (tester) async {
    final sendNotifier = _RecordingSendNotifier();
    late Ref ref;
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device', device: onlineDevice())],
      onRef: (r) => ref = r,
      overrides: [sendProvider.overrideWithNotifier((_) => sendNotifier)],
    );

    // 两栏选中设备后详情出现输入栏
    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'hello\nworld ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    // 全程不离开会话容器：只发生一次 conversation 模式的 startSession
    expect(sendNotifier.calls.length, 1);
    final call = sendNotifier.calls.single;
    expect(call.presentation, TransferPresentation.conversation);
    expect(call.background, isTrue);
    expect(call.target.fingerprint, 'AA:BB');
    // 消息协议格式：单 text 文件 + UTF8 原文（尾部空格不 trim）
    expect(call.files.single.fileType, FileType.text);
    expect(utf8.decode(call.files.single.bytes!), 'hello\nworld ');

    // 发送已提交：本设备草稿被清除
    expect(ref.read(conversationUiProvider).drafts.containsKey('fp:aaa'), isFalse);
  });

  testWidgets('P6c 离线设备：发送不可用，不产生任何 session 调用', (tester) async {
    final sendNotifier = _RecordingSendNotifier();
    await pumpTab(
      tester,
      width: 1000,
      // 离线投影：device 为 null（接线层双保险的另一半在 composer enabled）
      views: [fakeView('fp:aaa', alias: 'Offline Device', online: false)],
      onRef: (_) {},
      overrides: [sendProvider.overrideWithNotifier((_) => sendNotifier)],
    );

    await tester.tap(find.text('Offline Device'));
    await tester.pumpAndSettle();

    // 点击发送按钮（enabled=false 时 onPressed 为 null，点击无效）
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sendNotifier.calls, isEmpty);
    // 离线仍可查看历史：详情顶栏展示离线提示
    expect(find.text(t.conversation.offline), findsOneWidget);
  });
}
