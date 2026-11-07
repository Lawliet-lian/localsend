import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/conversation_receive_card_vm.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_app/pages/tabs/conversation_tab.dart';
import 'package:localsend_app/provider/conversation_attachment_provider.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/conversation_ui_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/conversation_attachment_cache.dart';
import 'package:localsend_app/widget/conversation/conversation_receive_card.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../mocks.mocks.dart';

/// P5 会话入口接线测试 + P6c 文字发送接线测试 + P7c 接收卡片接线测试。
/// 用 overrideWithBuilder 注入 fake 投影结果，不启动 Rust/isolate（方案 9.1）；
/// 发送路径用 fake SendNotifier 替换（startSession 真实实现依赖 Rust http）；
/// 接收卡片用 override 后的 conversationReceiveCardProvider 注入（真实 provider 需碰
/// ServerService/settings 持久化链）；peer 匹配逻辑走真实代码（session.sender 指纹）；
/// conversationUiProvider 使用真实实例；conversationProvider（P8）依赖 persistenceProvider，
/// 故用 MockPersistenceService 覆盖并回空历史（不落盘，等价于纯内存投影）。

/// 替换真实发送：只记录调用参数，不碰网络
/// （验证 presentation=conversation 接线与原文编码，不验证传输本身）
class _RecordingSendNotifier extends SendNotifier {
  final calls = <({Device target, List<CrossFile> files, bool background, TransferPresentation presentation})>[];

  /// 注入一个未关闭的 session（模拟 P9b 活跃发送门槛；state 是 protected，只能子类内赋值）
  void seedActiveSession() {
    state = {
      'active-1': SendSessionState(
        sessionId: 'active-1',
        remoteSessionId: 'remote-1',
        background: true,
        status: SessionStatus.sending,
        target: Device(
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
        ),
        files: const {},
        hashedFileCount: 0,
        startTime: null,
        endTime: null,
        sendingTasks: const [],
        errorMessage: null,
      ),
    };
  }

  @override
  Future<void> startSession({
    required Device target,
    required List<CrossFile> files,
    required bool background,
    TransferPresentation presentation = TransferPresentation.legacy,
    ConversationAttachmentCache? attachmentCache,
  }) async {
    calls.add((target: target, files: files, background: background, presentation: presentation));
  }
}

/// 替换真实附件协调：只记录 pickAndSend 调用（真实实现会打开原生 picker 弹层），
/// 并可注入 picking 状态验证选择器期间的发送/切设备锁。
class _RecordingAttachmentService extends ConversationAttachmentService {
  final picks = <Device>[];

  void seedPicking(bool value) {
    state = ConversationAttachmentState(picking: value);
  }

  @override
  Future<void> pickAndSend(
    BuildContext context, {
    required Device target,
  }) async {
    picks.add(target);
  }
}

void main() {
  ConversationPeerView fakeView(
    String peerKey, {
    String alias = 'Fake Peer',
    bool online = true,
    Device? device,
    bool hasActiveReceive = false,
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
      hasActiveReceive: hasActiveReceive,
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
    // P8：conversationProvider 现在会读取 persistenceProvider（无 override 则抛异常）。
    // 这里注入一个返回空历史的 mock：init() 走纯内存起点，after() 落盘为 mock no-op，
    // 与旧有"纯内存、不碰磁盘"的接线测试契约等价。
    final persistence = MockPersistenceService();
    when(persistence.getConversationHistory()).thenReturn(ConversationHistoryDto.empty());
    await tester.pumpWidget(
      RefenaScope(
        overrides: [
          persistenceProvider.overrideWithValue(persistence),
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
  /// localSessionId 可指定：同一 peer 播种多条时需要不同 id（entryId 去重键）。
  void seedEntry(Ref ref, String peerKey, String text, {String localSessionId = 's-1'}) {
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
            localSessionId: localSessionId,
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

  // ---- P7c 接收卡片接线 ----

  ReceiveSessionState vmSession({String fingerprint = 'AA:BB'}) {
    return ReceiveSessionState(
      sessionId: 'session-r1',
      status: SessionStatus.waiting,
      sender: onlineDevice().copyWith(fingerprint: fingerprint),
      senderAlias: 'Nick',
      files: {
        'f1': ReceivingFile(
          file: FileDto(id: 'f1', fileName: 'photo.jpg', size: 100, fileType: FileType.image, hash: null, preview: null, metadata: null),
          token: null,
          desiredName: null,
          path: null,
          savedToGallery: false,
          errorMessage: null,
        ),
      },
      startTime: null,
      endTime: null,
      destinationDirectory: '/tmp',
      cacheDirectory: '/tmp/cache',
      saveToGallery: false,
      createdDirectories: {},
    );
  }

  ConversationReceiveCardVm cardVm({String fingerprint = 'AA:BB'}) {
    return ConversationReceiveCardVm(
      session: vmSession(fingerprint: fingerprint),
      progressOf: (_) => 0,
    );
  }

  testWidgets('P7c 选中对端设备：卡片渲染；点拒绝转发 declineFileRequest 不报错', (tester) async {
    // 必须传入稳定实例：ViewProvider 按 identity 比较，builder 每次新 VM 会造成重建循环
    final card = cardVm();
    await pumpTab(
      tester,
      width: 1000,
      // 设备 peerKey 必须等于 peerKeyFor(session.sender.fingerprint='AA:BB') = 'fp:aa:bb'，匹配才渲染卡片
      views: [fakeView('fp:aa:bb', alias: 'Real Device', device: onlineDevice(), hasActiveReceive: true)],
      onRef: (_) {},
      overrides: [conversationReceiveCardProvider.overrideWithBuilder((_) => card)],
    );

    await tester.tap(find.text('Real Device'));
    // 有活跃接收时列表项是无限旋转的 CircularProgressIndicator，不能 pumpAndSettle（会超时），用单帧 pump
    await tester.pump();

    // 卡片只属于对端设备：peerKey 匹配走真实逻辑（fp:aa:bb ↔ 指纹 AA:BB）
    expect(find.byType(ConversationReceiveCard), findsOneWidget);
    expect(find.text(t.conversation.receiveCard.title(name: 'Nick')), findsOneWidget);

    // 真实 ServerService 的 declineFileRequest：state 为 null 时首行 guard 直接 return（安全 no-op）；
    // 本点击验证的是接线可达性——按钮存在且可点击不抛异常
    await tester.tap(find.text(t.general.decline));
    await tester.pump();
    expect(find.byType(ConversationReceiveCard), findsOneWidget);
  });

  testWidgets('P7c 选中非对端设备：卡片不展示（无双套按钮串设备）', (tester) async {
    final card = cardVm(fingerprint: 'BB:CC');
    await pumpTab(
      tester,
      width: 1000,
      // session 对端指纹 BB:CC → peerKey fp:bb:cc，与选中设备 fp:aa:bb 不匹配
      views: [fakeView('fp:aa:bb', alias: 'Real Device', device: onlineDevice(), hasActiveReceive: true)],
      onRef: (_) {},
      overrides: [conversationReceiveCardProvider.overrideWithBuilder((_) => card)],
    );

    await tester.tap(find.text('Real Device'));
    await tester.pump();

    expect(find.byType(ConversationReceiveCard), findsNothing);
  });

  testWidgets('P7c 无卡片投影（legacy/无 session）：详情页无接收卡片', (tester) async {
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device', device: onlineDevice())],
      onRef: (_) {},
      overrides: [conversationReceiveCardProvider.overrideWithBuilder((_) => null)],
    );

    await tester.tap(find.text('Real Device'));
    await tester.pump();

    expect(find.byType(ConversationReceiveCard), findsNothing);
    // 原有功能不受影响：输入栏仍在
    expect(find.byIcon(Icons.send), findsOneWidget);
  });

  // ---- P9a-3 清空当前会话（按设备）接线 ----

  testWidgets('P9a-3 菜单确认后：只清当前 peer 记录，其他 peer 记录与设备展示保留', (tester) async {
    late Ref ref;
    await pumpTab(
      tester,
      width: 1000,
      views: [
        fakeView('fp:aaa', alias: 'Real Device'),
        fakeView('fp:bbb', alias: 'Other Device'),
      ],
      onRef: (r) => ref = r,
    );
    seedEntry(ref, 'fp:aaa', 'hello one', localSessionId: 's-a1');
    seedEntry(ref, 'fp:aaa', 'hello two', localSessionId: 's-a2');
    seedEntry(ref, 'fp:bbb', 'other note', localSessionId: 's-b1');
    await tester.pump();

    // 选中设备 → 顶栏菜单 → 清空当前会话
    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.conversation.clearConversation));
    await tester.pumpAndSettle();

    // 确认弹窗文案携带对端别名（clearPeerDialog.content 的 {name} 插值）
    expect(find.text(t.conversation.clearPeerDialog.content(name: 'Real Device')), findsOneWidget);

    await tester.tap(find.text(t.general.delete));
    await tester.pumpAndSettle();

    // 选中设备的记录被清空：气泡消失，tombstone 已登记（晚到事件不复活由 provider 层单测覆盖）
    final state = ref.read(conversationProvider);
    expect(state.entries.where((e) => e.peerKey == 'fp:aaa'), isEmpty);
    expect(find.text('hello one'), findsNothing);
    // 门槛：只清该 peer——其他设备的记录不受影响
    expect(state.entries.where((e) => e.peerKey == 'fp:bbb').length, 1);
    // 门槛：保留 peer 展示信息——设备仍在列表（列表项 + 详情顶栏共 2 处）
    expect(find.text('Real Device'), findsNWidgets(2));
    expect(state.peers.any((p) => p.peerKey == 'fp:aaa'), isTrue);
  });

  testWidgets('P9a-3 弹窗取消：不清除任何记录，对话框关闭', (tester) async {
    late Ref ref;
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device')],
      onRef: (r) => ref = r,
    );
    seedEntry(ref, 'fp:aaa', 'keep me', localSessionId: 's-a1');
    await tester.pump();

    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.conversation.clearConversation));
    await tester.pumpAndSettle();

    // 取消：不 dispatch，弹窗关闭，记录原样保留
    await tester.tap(find.text(t.general.cancel));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(ref.read(conversationProvider).entries.length, 1);
    expect(find.text('keep me'), findsOneWidget);
  });

  // ---- P9b 附件即选即发接线 ----

  testWidgets('P9b 点附件按钮：转发 pickAndSend，目标固定为当前选中设备', (tester) async {
    final attachment = _RecordingAttachmentService();
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device', device: onlineDevice())],
      onRef: (_) {},
      overrides: [conversationAttachmentProvider.overrideWithNotifier((_) => attachment)],
    );

    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();

    // 门槛满足（selection 空、无活跃发送）：按钮可用，点击只转发不弹原生 picker
    await tester.tap(find.byIcon(Icons.attach_file));
    await tester.pump();

    expect(attachment.picks.length, 1);
    expect(attachment.picks.single.fingerprint, 'AA:BB');
  });

  testWidgets('C1 旧发送页有选件时会话仍可选附件', (tester) async {
    late Ref ref;
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device', device: onlineDevice())],
      onRef: (r) => ref = r,
    );
    ref
        .redux(selectedSendingFilesProvider)
        .dispatch(
          AddBinaryAction(bytes: Uint8List.fromList([1]), fileType: FileType.other, fileName: 'old.bin'),
        );

    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();

    final attachButton = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.attach_file), matching: find.byType(IconButton)),
    );
    expect(attachButton.onPressed, isNotNull);
  });

  testWidgets('C1 已有发送任务时会话仍可选附件', (tester) async {
    final sendNotifier = _RecordingSendNotifier();
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Real Device', device: onlineDevice())],
      onRef: (_) {},
      overrides: [sendProvider.overrideWithNotifier((_) => sendNotifier)],
    );
    // 必须在容器挂载后注入：挂载前赋值会被 Notifier.init() 的空 map 覆盖
    sendNotifier.seedActiveSession();
    await tester.pump();

    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();

    final attachButton = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.attach_file), matching: find.byType(IconButton)),
    );
    expect(attachButton.onPressed, isNotNull);
  });

  testWidgets('P9b picking 锁：选择器期间切设备被忽略、发送按钮禁用', (tester) async {
    final attachment = _RecordingAttachmentService();
    late Ref ref;
    await pumpTab(
      tester,
      width: 1000,
      views: [
        fakeView('fp:aaa', alias: 'Real Device', device: onlineDevice()),
        fakeView('fp:bbb', alias: 'Other Device', device: onlineDevice()),
      ],
      onRef: (r) => ref = r,
      overrides: [conversationAttachmentProvider.overrideWithNotifier((_) => attachment)],
    );

    await tester.tap(find.text('Real Device'));
    await tester.pumpAndSettle();

    // 模拟选择器打开：picking=true 后接线层应锁住切设备与发送
    attachment.seedPicking(true);
    await tester.pump();

    await tester.tap(find.text('Other Device'));
    await tester.pump();
    // 选中不变：快照一定发给打开选择器时的设备（方案 6.3）
    expect(ref.read(conversationUiProvider).selectedPeerKey, 'fp:aaa');

    // 发送按钮禁用（锁只针对提交动作，草稿输入框仍在）
    final sendButton = tester.widget<IconButton>(
      find.ancestor(of: find.byIcon(Icons.send), matching: find.byType(IconButton)),
    );
    expect(sendButton.onPressed, isNull);

    // 选择器关闭：锁释放，切设备恢复可用
    attachment.seedPicking(false);
    await tester.pump();
    await tester.tap(find.text('Other Device'));
    await tester.pump();
    expect(ref.read(conversationUiProvider).selectedPeerKey, 'fp:bbb');
  });

  testWidgets('P9b 离线设备：附件按钮不渲染（不支持的入口不出现）', (tester) async {
    await pumpTab(
      tester,
      width: 1000,
      views: [fakeView('fp:aaa', alias: 'Offline Device', online: false)],
      onRef: (_) {},
    );

    await tester.tap(find.text('Offline Device'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.attach_file), findsNothing);
  });
}
