import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_receive_card_vm.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_app/widget/conversation/conversation_receive_card.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// P7c：接收卡片的 widget 测试（dumb 组件合同：三态渲染 + 回调参数）。
/// 卡片内部 watch fileTransferProvider（进度订阅），所以必须包 RefenaScope。
void main() {
  Device sender() {
    return Device(
      signalingId: null,
      ip: '10.0.0.1',
      version: '2.1',
      port: 53317,
      https: true,
      fingerprint: 'AA:BB',
      alias: 'Alias',
      deviceModel: 'model',
      deviceType: DeviceType.mobile,
      download: false,
      channels: const [],
    );
  }

  ReceivingFile file(String id, {String? desiredName}) {
    return ReceivingFile(
      file: FileDto(
        id: id,
        fileName: '$id.bin',
        size: 10,
        fileType: FileType.image,
        hash: null,
        preview: null,
        metadata: null,
      ),
      token: null,
      desiredName: desiredName,
      path: null,
      savedToGallery: false,
      errorMessage: null,
    );
  }

  ConversationReceiveCardVm vm(
    Map<String, ReceivingFile> files, {
    SessionStatus status = SessionStatus.waiting,
    double Function(String fileId)? progressOf,
  }) {
    return ConversationReceiveCardVm(
      session: ReceiveSessionState(
        sessionId: 'session-1',
        status: status,
        sender: sender(),
        senderAlias: 'Nick',
        files: files,
        startTime: null,
        endTime: null,
        destinationDirectory: '/tmp',
        cacheDirectory: '/tmp/cache',
        saveToGallery: false,
        createdDirectories: {},
      ),
      progressOf: progressOf ?? (_) => 0,
    );
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    required ConversationReceiveCardVm cardVm,
    void Function(Map<String, String>)? onAccept,
    VoidCallback? onDecline,
    VoidCallback? onCancel,
    VoidCallback? onClose,
  }) async {
    tester.view.physicalSize = const Size(600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RefenaScope(
        child: MaterialApp(
          home: Scaffold(
            body: ConversationReceiveCard(
              vm: cardVm,
              onAccept: onAccept ?? (_) {},
              onDecline: onDecline ?? () {},
              onCancel: onCancel ?? () {},
              onClose: onClose ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('waiting：默认全选、展示接受/拒绝按钮与文件名', (tester) async {
    Map<String, String>? accepted;
    await pumpCard(
      tester,
      cardVm: vm({'f1': file('f1'), 'f2': file('f2')}),
      onAccept: (map) => accepted = map,
    );

    expect(find.text(t.conversation.receiveCard.title(name: 'Nick')), findsOneWidget);
    expect(find.text('f1.bin'), findsOneWidget);
    expect(find.text('f2.bin'), findsOneWidget);
    expect(find.text(t.general.accept), findsOneWidget);
    expect(find.text(t.general.decline), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing); // 取消/关闭按钮不属于待决态

    // 默认全选：点击接受携带完整 fileNameMap（desiredName 优先）
    await tester.tap(find.text(t.general.accept));
    await tester.pump();
    expect(accepted, {'f1': 'f1.bin', 'f2': 'f2.bin'});
  });

  testWidgets('waiting：取消勾选一个文件后接受只含剩余项；禁止取消最后一个勾选', (tester) async {
    Map<String, String>? accepted;
    await pumpCard(
      tester,
      cardVm: vm({'f1': file('f1'), 'f2': file('f2', desiredName: 'kept.bin')}),
      onAccept: (map) => accepted = map,
    );

    // 取消第一个勾选
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    // 再尝试取消第二个（最后一个已勾选）：应被拒绝，未勾选数仍为 1（只剩 f1）
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Checkbox && w.value == false), findsOneWidget);

    // 接受：只含未取消的 f2（desiredName 优先）
    await tester.tap(find.text(t.general.accept));
    await tester.pump();
    expect(accepted, {'f2': 'kept.bin'});
  });

  testWidgets('sending：展示进度条与取消按钮，不再出现勾选/接受', (tester) async {
    var cancelClicked = false;
    await pumpCard(
      tester,
      cardVm: vm(
        {'f1': file('f1', desiredName: 'f1.bin')},
        status: SessionStatus.sending,
        progressOf: (_) => 0.5,
      ),
      onCancel: () => cancelClicked = true,
    );

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text(t.general.accept), findsNothing);
    expect(find.text(t.general.cancel), findsOneWidget);

    await tester.tap(find.text(t.general.cancel));
    await tester.pump();
    expect(cancelClicked, isTrue);
  });

  testWidgets('canceledBySender：展示提示与关闭按钮，无接受/拒绝/取消', (tester) async {
    var closed = false;
    await pumpCard(
      tester,
      cardVm: vm({'f1': file('f1')}, status: SessionStatus.canceledBySender),
      onClose: () => closed = true,
    );

    expect(find.text(t.conversation.receiveCard.canceled), findsOneWidget);
    expect(find.text(t.general.close), findsOneWidget);
    expect(find.text(t.general.accept), findsNothing);
    expect(find.text(t.general.decline), findsNothing);
    expect(find.text(t.general.cancel), findsNothing);

    await tester.tap(find.text(t.general.close));
    await tester.pump();
    expect(closed, isTrue);
  });

  testWidgets('超过 4 个文件折叠展示"+n 更多"', (tester) async {
    await pumpCard(
      tester,
      cardVm: vm({
        for (var i = 0; i < 6; i++) 'f$i': file('f$i'),
      }),
    );

    expect(find.byType(ListTile), findsNothing);
    expect(find.text(t.conversation.receiveCard.moreFiles(n: 2)), findsOneWidget);
    // 前 4 个可见，后 2 个折叠
    expect(find.text('f0.bin'), findsOneWidget);
    expect(find.text('f4.bin'), findsNothing);
  });
}
