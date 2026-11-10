import 'dart:async';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/provider/conversation_attachment_provider.dart';
import 'package:localsend_app/provider/conversation_file_draft_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/transfer_presentation_provider.dart';
import 'package:localsend_app/util/native/cache_helper.dart';
import 'package:localsend_app/util/native/conversation_attachment_cache.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:refena_flutter/refena_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RefenaContainer container;
  late _RecordingSendNotifier sendNotifier;

  Device target({String ip = '10.0.0.1'}) {
    return Device(
      signalingId: null,
      ip: ip,
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
  SendSessionState activeSession({SessionStatus status = SessionStatus.sending}) {
    return SendSessionState(
      sessionId: 'active-1',
      remoteSessionId: 'remote-1',
      background: true,
      status: status,
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

  const desktop = TargetPlatformVariant({TargetPlatform.macOS});
  const mobile = TargetPlatformVariant({TargetPlatform.android});

  test('staged mobile files survive shared temporary cleanup until the transfer stops reading', () async {
    final root = await Directory.systemTemp.createTemp('attachment-cache-test-');
    addTearDown(() => root.delete(recursive: true));
    final source = await File('${root.path}/picked.jpg').writeAsString('image data');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      return switch (call.method) {
        'getTemporaryDirectory' || 'getApplicationCacheDirectory' => root.path,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    final cache = ConversationAttachmentCache();
    final files = await cache.stage([_desktopFile('picked.jpg').copyWith(path: source.path)], copyImportedFiles: false);
    final copy = File(files.single.path!);
    await clearTemporaryCacheFiles(root);
    expect(await source.exists(), false);

    await cache.use(() async {
      cache.close();
      expect(await copy.readAsString(), 'image data');
    });
    expect(await copy.exists(), false);
  });

  testWidgets('desktop clipboard picker returns its own selection', variant: desktop, (tester) async {
    pickBinary('legacy.bin');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      return call.method == 'Clipboard.getData' ? {'text': 'copied text'} : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    final result = container.notifier(conversationAttachmentProvider).pickFiles(context, ConversationAttachmentCache());
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.sendTab.picker.clipboard));
    await tester.pumpAndSettle();

    expect((await result).single.bytes, 'copied text'.codeUnits);
    expect(container.read(selectedSendingFilesProvider).single.name, 'legacy.bin');
  });

  testWidgets('mobile sends consecutive picks independently of the legacy selection and sessions', variant: mobile, (tester) async {
    final context = await pumpContext(tester);
    final updatedDevice = target(ip: 'fe80::1%3');
    final selectedFiles = <CrossFile>[];
    final isolatedContainer = RefenaContainer(
      overrides: [
        sendProvider.overrideWithNotifier((_) => sendNotifier),
        conversationAttachmentProvider.overrideWithNotifier((_) => _TestAttachmentService(() async => selectedFiles)),
        conversationPeerViewsProvider.overrideWithBuilder(
          (_) => [
            ConversationPeerView(
              peerKey: 'fp:aa:bb',
              alias: updatedDevice.alias,
              deviceType: updatedDevice.deviceType,
              online: true,
              device: updatedDevice,
              lastEntry: null,
              entryCount: 0,
              hasActiveSend: false,
              hasActiveReceive: false,
            ),
          ],
        ),
      ],
    );
    addTearDown(isolatedContainer.disposeContainer);

    isolatedContainer
        .redux(selectedSendingFilesProvider)
        .dispatch(
          AddBinaryAction(bytes: Uint8List.fromList([1]), fileType: FileType.other, fileName: 'legacy.bin'),
        );
    sendNotifier.seedActiveSession(activeSession(status: SessionStatus.finishedWithErrors));
    final service = isolatedContainer.notifier(conversationAttachmentProvider);

    selectedFiles.add(_desktopFile('first.bin'));
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), true);
    await service.pickAndSend(context, target: target());
    selectedFiles[0] = _desktopFile('second.bin');
    await service.pickAndSend(context, target: target());

    expect(sendNotifier.calls.map((call) => call.files.single.name), ['first.bin', 'second.bin']);
    expect(sendNotifier.calls.map((call) => call.target.ip), everyElement('fe80::1%3'));
    expect(isolatedContainer.read(selectedSendingFilesProvider).single.name, 'legacy.bin');
  });

  testWidgets('desktop does not submit a pick if the original peer is no longer discovered', variant: desktop, (tester) async {
    final context = await pumpContext(tester);
    final isolatedContainer = RefenaContainer(
      overrides: [
        sendProvider.overrideWithNotifier((_) => sendNotifier),
        conversationAttachmentProvider.overrideWithNotifier((_) => _TestAttachmentService(() async => [_desktopFile('picked.bin')])),
        conversationPeerViewsProvider.overrideWithBuilder((_) => const []),
      ],
    );
    addTearDown(isolatedContainer.disposeContainer);

    await isolatedContainer.notifier(conversationAttachmentProvider).pickAndSend(context, target: target());
    expect(sendNotifier.calls, isEmpty);
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), true);
  });

  testWidgets('closing a finished mobile conversation session leaves legacy selection intact', variant: mobile, (tester) async {
    pickBinary('legacy.bin');
    final session = activeSession(status: SessionStatus.finished);
    sendNotifier.seedActiveSession(session);
    container.notifier(transferPresentationProvider).set(session.sessionId, TransferPresentation.conversation);

    sendNotifier.closeSession(session.sessionId);

    expect(container.read(sendProvider), isEmpty);
    expect(container.read(selectedSendingFilesProvider).single.name, 'legacy.bin');
  });

  test('changing the legacy send mode leaves conversation transfers and presentations intact', () {
    final legacy = activeSession();
    final conversation = activeSession().copyWith(sessionId: 'conversation');
    sendNotifier.seedActiveSessions([legacy, conversation]);
    final presentations = container.notifier(transferPresentationProvider);
    presentations.set(conversation.sessionId, TransferPresentation.conversation);
    presentations.set('receiving', TransferPresentation.conversation);
    expect(container.read(legacySendSessionsProvider).map((session) => session.sessionId), [legacy.sessionId]);

    sendNotifier.clearLegacySessions();

    expect(container.read(sendProvider).keys, [conversation.sessionId]);
    expect(presentations.get(conversation.sessionId), TransferPresentation.conversation);
    expect(presentations.get('receiving'), TransferPresentation.conversation);
  });

  testWidgets('mobile picker keeps its lock through selection and releases it on cancellation', variant: mobile, (tester) async {
    final context = await pumpContext(tester);
    final picker = Completer<List<CrossFile>>();
    var calls = 0;
    final isolatedContainer = RefenaContainer(
      overrides: [
        sendProvider.overrideWithNotifier((_) => sendNotifier),
        conversationAttachmentProvider.overrideWithNotifier(
          (_) => _TestAttachmentService(() {
            calls++;
            return picker.future;
          }),
        ),
      ],
    );
    addTearDown(isolatedContainer.disposeContainer);

    final service = isolatedContainer.notifier(conversationAttachmentProvider);
    final pending = service.pickAndSend(context, target: target());
    await tester.pump();
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), false);
    await service.pickAndSend(context, target: target());
    expect(calls, 1);

    picker.complete([]);
    await pending;
    await tester.pump();
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), true);
    expect(sendNotifier.calls, isEmpty);
  });

  testWidgets('removing a picked draft allows picking another one', variant: mobile, (tester) async {
    final context = await pumpContext(tester);
    var calls = 0;
    final isolatedContainer = RefenaContainer(
      overrides: [
        conversationAttachmentProvider.overrideWithNotifier(
          (_) => _TestAttachmentService(() async {
            calls++;
            return [_desktopFile('file$calls')];
          }),
        ),
      ],
    );
    addTearDown(isolatedContainer.disposeContainer);
    final service = isolatedContainer.notifier(conversationAttachmentProvider);
    await service.pickToDraft(context, peerKey: 'peer');
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), isTrue);
    expect(isolatedContainer.read(conversationFileDraftProvider)['peer']!.single.name, 'file1');
    isolatedContainer.notifier(conversationFileDraftProvider).setFiles('peer', []);
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), isTrue);
    await service.pickToDraft(context, peerKey: 'peer');
    expect(isolatedContainer.read(conversationFileDraftProvider)['peer']!.single.name, 'file2');
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), isTrue);
  });

  testWidgets('dropped files are added to the selected draft without starting a transfer', (tester) async {
    final context = await pumpContext(tester);
    final isolatedContainer = RefenaContainer(
      overrides: [
        sendProvider.overrideWithNotifier((_) => sendNotifier),
        conversationAttachmentProvider.overrideWithNotifier((_) => _DroppedAttachmentService()),
      ],
    );
    addTearDown(isolatedContainer.disposeContainer);
    await isolatedContainer
        .notifier(conversationAttachmentProvider)
        .addDroppedFilesToDraft(
          context,
          peerKey: 'peer',
          files: [DropItemFile('/files/a')],
        );
    expect(isolatedContainer.read(conversationFileDraftProvider)['peer']!.single.name, 'dropped.txt');
    expect(sendNotifier.calls, isEmpty);
    expect(isolatedContainer.read(conversationAttachmentEnabledProvider), isTrue);
  });

  testWidgets('Android picker returns a SAF URI without modifying legacy selection', variant: mobile, (tester) async {
    pickBinary('legacy.bin');
    const channel = MethodChannel('org.localsend.localsend_app/localsend');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const uri = 'content://com.android.externalstorage.documents/document/test';
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method != 'pickFiles') {
        return null;
      }
      return [
        {'name': 'picked.txt', 'size': 10, 'uri': uri, 'lastModified': null},
      ];
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold();
          },
        ),
      ),
    );
    final cache = ConversationAttachmentCache();
    final pending = container.notifier(conversationAttachmentProvider).pickFiles(context, cache);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.sendTab.picker.file));
    await tester.pumpAndSettle();

    expect((await pending).single.path, uri);
    expect(cache.hasFiles, false);
    expect(container.read(selectedSendingFilesProvider).single.name, 'legacy.bin');
  });
}

CrossFile _desktopFile(String name) => CrossFile(
  name: name,
  fileType: FileType.other,
  size: 1,
  thumbnail: null,
  asset: null,
  path: '/files/$name',
  bytes: null,
  lastModified: null,
  lastAccessed: null,
);

class _TestAttachmentService extends ConversationAttachmentService {
  _TestAttachmentService(this.files);

  final Future<List<CrossFile>> Function() files;

  @override
  Future<List<CrossFile>> pickFiles(BuildContext context, ConversationAttachmentCache cache) => files();
}

class _DroppedAttachmentService extends ConversationAttachmentService {
  @override
  Future<List<CrossFile>> convertDroppedFiles(List<DropItem> files, ConversationAttachmentCache cache) async => [_desktopFile('dropped.txt')];
}

/// 替换真实发送：只记录调用参数，不碰网络
class _RecordingSendNotifier extends SendNotifier {
  final calls = <({Device target, List<CrossFile> files, bool background, TransferPresentation presentation})>[];

  /// 注入一个未关闭的 session（模拟活跃发送门槛；state 是 protected，只能子类内赋值）
  void seedActiveSession(SendSessionState session) {
    seedActiveSessions([session]);
  }

  void seedActiveSessions(List<SendSessionState> sessions) {
    state = {for (final session in sessions) session.sessionId: session};
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
