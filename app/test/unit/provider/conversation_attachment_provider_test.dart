import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/provider/conversation_attachment_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// P9b-1：会话附件选择协调 provider 的单元测试（方案 6.3 门槛）。
///
/// 真实 picker 依赖原生平台通道无法纯 Dart 运行，故 pickAndSend 的 [pick]
/// 参数注入选择器行为：fake picker 向**真实** selectedSendingFilesProvider
/// 写入文件（与 PickFileAction 的实际副作用一致），验证门槛/锁/快照/编排合同。
/// 发送用 fake SendNotifier 替换（startSession 真实实现依赖 Rust http）。
void main() {
  late RefenaContainer container;
  late _RecordingSendNotifier sendNotifier;

  Device target() {
    return Device(
      signalingId: null,
      ip: '10.0.0.1',
      version: '2.1',
      port: 53317,
      https: true,
      fingerprint: 'AA:BB',
      alias: 'Target Device',
      deviceModel: 'model',
      deviceType: DeviceType.desktop,
      download: false,
      channels: const [],
    );
  }

  /// 向全局 selection 写入一个内存文件（模拟 picker 的 AddBinaryAction 副作用）
  void pickBinary(String name) {
    container
        .redux(selectedSendingFilesProvider)
        .dispatch(
          AddBinaryAction(bytes: Uint8List.fromList([1, 2, 3]), fileType: FileType.other, fileName: name),
        );
  }

  /// 构造一个未关闭的发送 session（模拟活跃发送门槛）
  SendSessionState activeSession() {
    return SendSessionState(
      sessionId: 'active-1',
      remoteSessionId: 'remote-1',
      background: true,
      status: SessionStatus.sending,
      target: target(),
      files: const {},
      hashedFileCount: 0,
      startTime: null,
      endTime: null,
      sendingTasks: const [],
      errorMessage: null,
    );
  }

  setUp(() {
    sendNotifier = _RecordingSendNotifier();
    container = RefenaContainer(
      overrides: [sendProvider.overrideWithNotifier((_) => sendNotifier)],
    );
  });

  tearDown(() {
    container.disposeContainer();
  });

  /// 提供一个真实 BuildContext（pickAndSend 签名需要；注入的 fake pick 不使用它）
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    return tester.element(find.byType(SizedBox));
  }

  group('门槛（方案 6.3：selection 为空且无活跃发送才允许）', () {
    testWidgets('testSelectionNotEmptyBlocksPick', (tester) async {
      final context = await pumpContext(tester);
      pickBinary('existing.bin'); // 旧 SendTab 已选了文件
      var pickCalls = 0;

      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async => pickCalls++,
          );

      // 选择器根本不打开，更不产生发送
      expect(pickCalls, 0);
      expect(sendNotifier.calls, isEmpty);
      expect(container.read(conversationAttachmentProvider).picking, false);
    });

    testWidgets('testActiveSendBlocksPick', (tester) async {
      final context = await pumpContext(tester);
      sendNotifier.seedActiveSession(activeSession());
      var pickCalls = 0;

      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async => pickCalls++,
          );

      expect(pickCalls, 0);
      expect(sendNotifier.calls, isEmpty);
    });

    testWidgets('testEnabledProjectionReflectsAllThreeFacts', (tester) async {
      await pumpContext(tester);
      // 默认：无选择、无发送、未 picking → 可用
      expect(container.read(conversationAttachmentEnabledProvider), true);

      // 活跃发送 → 不可用（保守判定：未 closeSession 的 session 都算活跃）
      sendNotifier.seedActiveSession(activeSession());
      // Notifier 的 state 变更通知走异步调度，flush 事件循环后再读投影
      await tester.pump();
      expect(container.read(conversationAttachmentEnabledProvider), false);
    });

    testWidgets('testEnabledProjectionBlockedBySelection', (tester) async {
      await pumpContext(tester);
      // 全局 selection 非空 → 不可用。
      // 注意：这里不做“清空后恢复 true”断言——清空 selection 的既有 action
      // 会连带触发 ClearCacheAction（原生 isolate/平台通道），超出纯 Dart 测试边界；
      // 缓存清理时机的正确性由生产代码既有路径保证（本批不改它）。
      pickBinary('a.bin');
      expect(container.read(conversationAttachmentEnabledProvider), false);
    });
  });

  group('即选即发编排', () {
    testWidgets('testPickThenSendConversationSnapshot', (tester) async {
      final context = await pumpContext(tester);

      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async => pickBinary('photo.png'),
          );

      // 一次 conversation 模式发送：目标固定、background、文件来自 picker 结果
      expect(sendNotifier.calls.length, 1);
      final call = sendNotifier.calls.single;
      expect(call.presentation, TransferPresentation.conversation);
      expect(call.background, isTrue);
      expect(call.target.fingerprint, 'AA:BB');
      expect(call.files.single.name, 'photo.png');
      // 锁已释放（锁只覆盖选择器期间，不覆盖 session 时长）
      expect(container.read(conversationAttachmentProvider).picking, false);
    });

    testWidgets('testCancelProducesNoTransfer', (tester) async {
      final context = await pumpContext(tester);

      // fake picker 什么都不写 = 用户取消
      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async {},
          );

      expect(sendNotifier.calls, isEmpty);
      expect(container.read(selectedSendingFilesProvider), isEmpty);
      expect(container.read(conversationAttachmentProvider).picking, false);
    });

    testWidgets('testSnapshotIsolatedFromLaterSelection', (tester) async {
      final context = await pumpContext(tester);

      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async => pickBinary('first.bin'),
          );

      // 发送提交后继续往全局 selection 加文件（模拟后续选择）：
      // 原任务的快照列表不受影响（不可变快照，方案 6.3）
      final snapshot = sendNotifier.calls.single.files;
      pickBinary('second.bin');
      expect(snapshot.length, 1);
      expect(snapshot.single.name, 'first.bin');
      expect(() => snapshot.add(sendNotifier.calls.single.files.first), throwsUnsupportedError);
    });

    testWidgets('testSelectionNotClearedByAttachmentFlow', (tester) async {
      final context = await pumpContext(tester);

      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async => pickBinary('keep.bin'),
          );

      // 门槛：本批绝不 dispatch ClearSelectionAction（它会清缓存）；
      // selection 保留，清理沿用 closeSession 的既有安全时机
      expect(container.read(selectedSendingFilesProvider).length, 1);
    });
  });

  group('picking 锁与异常安全', () {
    testWidgets('testPickingLocksDuringPickerAndBlocksReentry', (tester) async {
      final context = await pumpContext(tester);
      final pickerGate = Completer<void>();
      var pickCalls = 0;

      // 第一次调用：fake picker 挂起，模拟选择器打开期间
      final first = container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async {
              pickCalls++;
              await pickerGate.future;
              pickBinary('locked.bin');
            },
          );
      await tester.pump();

      expect(container.read(conversationAttachmentProvider).picking, true);
      // 门槛投影同步变 false（接线层据此锁发送与切设备）
      expect(container.read(conversationAttachmentEnabledProvider), false);

      // 第二次调用：picking 期间重入直接返回，选择器不会打开两次
      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async => pickCalls++,
          );
      expect(pickCalls, 1);

      pickerGate.complete();
      await first;
      expect(container.read(conversationAttachmentProvider).picking, false);
      expect(sendNotifier.calls.length, 1);
    });

    testWidgets('testPickerExceptionReleasesLock', (tester) async {
      final context = await pumpContext(tester);

      await container
          .notifier(conversationAttachmentProvider)
          .pickAndSend(
            context,
            target: target(),
            pick: () async => throw Exception('picker crashed'),
          );

      // finally 释放锁：异常不会把 UI 永久锁死，也不产生发送
      expect(container.read(conversationAttachmentProvider).picking, false);
      expect(sendNotifier.calls, isEmpty);
    });
  });
}

/// 替换真实发送：只记录调用参数，不碰网络
class _RecordingSendNotifier extends SendNotifier {
  final calls = <({Device target, List<CrossFile> files, bool background, TransferPresentation presentation})>[];

  /// 注入一个未关闭的 session（模拟活跃发送门槛；state 是 protected，只能子类内赋值）
  void seedActiveSession(SendSessionState session) {
    state = {session.sessionId: session};
  }

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
