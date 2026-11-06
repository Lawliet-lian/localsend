import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/conversation_receive_recorder.dart';
import 'package:localsend_app/provider/persistence_provider.dart';
import 'package:localsend_app/provider/transfer_presentation_provider.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_status.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';
import 'package:mockito/mockito.dart';
import 'package:refena_flutter/refena_flutter.dart';

import '../../mocks.mocks.dart';

/// P7b：接收会话记录器的单元测试。
/// 记录器是 receive_controller 全部接入点的实际执行者；onPrepareUpload 整体流程依赖
/// Rust/isolate/Routerino 无法纯 Dart 集成，故在此层验证接收侧记录合同。
void main() {
  const sessionId = 'session-1';
  const entryId = 'receive:session-1'; // ConversationEntry.buildEntryId(receive, sessionId)

  late RefenaContainer container;
  late ConversationReceiveRecorder recorder;

  Device sender() {
    return Device(
      signalingId: null,
      ip: '10.0.0.1',
      version: '2.1',
      port: 53317,
      https: true,
      fingerprint: 'AA:BB',
      alias: 'Raw Alias',
      deviceModel: 'model',
      deviceType: DeviceType.mobile,
      download: false,
      channels: const [],
    );
  }

  /// 接收侧文件条目；desiredName 为空 = 本端尚未接受该文件
  ReceivingFile receivingFile(
    String id, {
    String? desiredName,
    String? path,
    bool savedToGallery = false,
    String? error,
    FileType fileType = FileType.image,
    String? preview,
  }) {
    return ReceivingFile(
      file: FileDto(
        id: id,
        fileName: desiredName ?? '$id.bin',
        size: 10,
        fileType: fileType,
        hash: null,
        preview: preview,
        metadata: null,
      ),
      token: null,
      desiredName: desiredName,
      path: path,
      savedToGallery: savedToGallery,
      errorMessage: error,
    );
  }

  ReceiveSessionState session(
    Map<String, ReceivingFile> files, {
    SessionStatus status = SessionStatus.waiting,
    String senderAlias = 'Saved Nickname',
  }) {
    return ReceiveSessionState(
      sessionId: sessionId,
      status: status,
      sender: sender(),
      senderAlias: senderAlias,
      files: files,
      startTime: null,
      endTime: null,
      destinationDirectory: '/tmp',
      cacheDirectory: '/tmp/cache',
      saveToGallery: false,
      createdDirectories: {},
    );
  }

  ConversationEntry? entry() {
    return container.read(conversationProvider).entries.where((e) => e.entryId == entryId).singleOrNull;
  }

  setUp(() {
    // P8：真实 conversationProvider 依赖 persistenceProvider；注入回空历史的 mock，
    // 使记录器测试保持"纯内存投影"语义（init 走空起点，落盘为 mock no-op）。
    final persistence = MockPersistenceService();
    when(persistence.getConversationHistory()).thenReturn(ConversationHistoryDto.empty());
    container = RefenaContainer(overrides: [persistenceProvider.overrideWithValue(persistence)]);
    recorder = ConversationReceiveRecorder(container);
  });

  tearDown(() {
    container.disposeContainer();
  });

  /// 把 session 标记为会话展示模式（模拟 onPrepareUpload 的 P7a 判定结果）
  void markConversation() {
    container.notifier(transferPresentationProvider).set(sessionId, TransferPresentation.conversation);
  }

  group('ConversationReceiveRecorder', () {
    test('testLegacySessionProducesNoRecords', () {
      // 门槛：legacy 接收不产生任何会话记录（未记录 presentation = legacy）
      recorder.onSessionCreated(session: session({'f1': receivingFile('f1')}));
      recorder.onAccepted(session: session({'f1': receivingFile('f1', desiredName: 'f1.bin')}));
      recorder.onMessageAccepted(
        session: session({'f1': receivingFile('f1', fileType: FileType.text, preview: 'hi')}),
      );
      recorder.onTerminalSnapshot(session: session({'f1': receivingFile('f1')}), outcome: ConversationOutcome.finished);
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.declined);
      recorder.onClosing(session: session({'f1': receivingFile('f1')}));

      expect(container.read(conversationProvider).entries, isEmpty);
      expect(container.read(conversationProvider).peers, isEmpty);
    });

    test('testOnSessionCreatedRegistersWaitingEntry', () {
      markConversation();
      recorder.onSessionCreated(
        session: session({
          'f1': receivingFile('f1'),
          'f2': receivingFile('f2', fileType: FileType.text),
        }),
      );

      final e = entry()!;
      // 接收方向 + 稳定 peerKey（fp: 小写指纹）；alias 用 senderAlias（收藏备注优先）
      expect(e.direction, ConversationDirection.receive);
      expect(e.peerKey, 'fp:aa:bb');
      expect(e.localSessionId, sessionId);
      expect(e.kind, ConversationEntryKind.file);
      // 接收侧没有校验和阶段：请求一到即 waiting
      expect(e.outcome, ConversationOutcome.waiting);
      expect(e.finishedAt, isNull);
      expect(e.files.map((f) => f.fileId), ['f1', 'f2']);
      expect(e.files.every((f) => f.outcome == ConversationFileOutcome.pending), isTrue);
      // peer 展示名是收藏别名而非自报名
      expect(container.read(conversationProvider).peers.single.alias, 'Saved Nickname');
    });

    test('testMessageSessionRegistersKindTextVerbatim', () {
      markConversation();
      // 消息协议格式：单 text 文件 + preview 嵌正文（条件与 ReceiveSessionState.message 一致）
      recorder.onSessionCreated(
        session: session({
          'f1': receivingFile('f1', fileType: FileType.text, preview: '  hello\nworld  '),
        }),
      );

      final e = entry()!;
      expect(e.kind, ConversationEntryKind.text);
      // 正文原样：不 trim、保留换行（方案 6.2）
      expect(e.text, '  hello\nworld  ');
      expect(e.files, isEmpty);
    });

    test('testTextFileWithoutPreviewIsNotMessage', () {
      markConversation();
      // 单个 text 文件但无 preview = 普通文字文件传输，不是消息（与协议不分叉）
      recorder.onSessionCreated(
        session: session({
          'f1': receivingFile('f1', fileType: FileType.text, preview: null),
        }),
      );

      expect(entry()!.kind, ConversationEntryKind.file);
      expect(entry()!.text, isNull);
    });

    test('testOnAcceptedMarksTransferringAndSkipped', () {
      markConversation();
      recorder.onSessionCreated(
        session: session({
          'f1': receivingFile('f1'),
          'f2': receivingFile('f2'),
        }),
      );
      recorder.onAccepted(
        session: session({
          'f1': receivingFile('f1', desiredName: 'renamed.txt'),
          'f2': receivingFile('f2', desiredName: null), // 用户未勾选
        }, status: SessionStatus.sending),
      );

      final e = entry()!;
      expect(e.outcome, ConversationOutcome.transferring);
      expect(e.finishedAt, isNull);
      // 展示文件名改用用户确认的 desiredName
      expect(e.files.firstWhere((f) => f.fileId == 'f1').fileName, 'renamed.txt');
      expect(e.files.firstWhere((f) => f.fileId == 'f1').outcome, ConversationFileOutcome.pending);
      // 未接受的文件标 skipped
      expect(e.files.firstWhere((f) => f.fileId == 'f2').outcome, ConversationFileOutcome.skipped);
    });

    test('testOnTerminalSnapshotRecordsResultsAndPaths', () {
      markConversation();
      final files = {
        'f1': receivingFile('f1', desiredName: 'a.png', path: '/tmp/a.png', savedToGallery: true),
        'f2': receivingFile('f2', desiredName: 'b.bin', error: 'checksum mismatch'),
      };
      recorder.onSessionCreated(session: session(files));
      // 模拟 isolate 回报的每文件实时结果
      container
          .notifier(fileTransferProvider)
          .setStatuses(
            sessionId: sessionId,
            statuses: {
              'f1': FileStatus.finished,
              'f2': FileStatus.failed,
            },
          );
      recorder.onTerminalSnapshot(
        session: session(files, status: SessionStatus.finishedWithErrors),
        outcome: ConversationOutcome.partialFailure,
      );

      final e = entry()!;
      expect(e.outcome, ConversationOutcome.partialFailure);
      expect(e.finishedAt, isNotNull);
      final f1 = e.files.firstWhere((f) => f.fileId == 'f1');
      expect(f1.outcome, ConversationFileOutcome.success);
      // 接收方向记录真实保存路径与相册结果
      expect(f1.path, '/tmp/a.png');
      expect(f1.savedToGallery, isTrue);
      final f2 = e.files.firstWhere((f) => f.fileId == 'f2');
      expect(f2.outcome, ConversationFileOutcome.failure);
      // 单文件错误放在文件摘要里
      expect(f2.error, 'checksum mismatch');
    });

    test('testOnMessageAcceptedFinishes', () {
      markConversation();
      final messageSession = session({'f1': receivingFile('f1', fileType: FileType.text, preview: 'hi there')});
      recorder.onSessionCreated(session: messageSession);
      // 空选择 accept（204）即消息确认送达
      recorder.onMessageAccepted(session: messageSession);

      expect(entry()!.outcome, ConversationOutcome.finished);
      expect(entry()!.finishedAt, isNotNull);
    });

    test('testDeclineAndCancelRecordTerminalStates', () {
      markConversation();
      recorder.onSessionCreated(session: session({'f1': receivingFile('f1')}));
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.declined);
      expect(entry()!.outcome, ConversationOutcome.declined);
      expect(entry()!.finishedAt, isNotNull);

      // 发送端取消场景
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.canceledBySender);
      expect(entry()!.outcome, ConversationOutcome.canceledBySender);
    });

    test('testOnClosingFinalizesOpenEntry', () {
      markConversation();
      final files = {'f1': receivingFile('f1')};
      recorder.onSessionCreated(session: session(files));
      // 用户在等待中直接离开页面：closeSession 收口为 canceledByReceiver（本端中止）
      recorder.onClosing(session: session(files));

      expect(entry()!.outcome, ConversationOutcome.canceledByReceiver);
      expect(entry()!.finishedAt, isNotNull);
    });

    test('testOnClosingDoesNotOverrideTerminalState', () {
      markConversation();
      final files = {'f1': receivingFile('f1')};
      recorder.onSessionCreated(session: session(files));
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.declined);
      // decline 之后 ReceivePage onClose 还会触发 closeSession——不得覆盖已记录的终态
      recorder.onClosing(session: session(files));

      expect(entry()!.outcome, ConversationOutcome.declined);
    });

    test('testRepeatedUpsertDoesNotAppend', () {
      // 门槛：重复事件 upsert 不追加新气泡
      markConversation();
      final files = {'f1': receivingFile('f1')};
      recorder.onSessionCreated(session: session(files));
      recorder.onSessionCreated(session: session(files));
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.waiting);
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.transferring);

      expect(container.read(conversationProvider).entries.length, 1);
      expect(entry()!.outcome, ConversationOutcome.transferring);
    });

    test('testUpdateWithoutRegisteredEntryIsNoop', () {
      markConversation();
      // 未登记直接 update 不凭空造记录
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.declined);
      recorder.onClosing(session: session({'f1': receivingFile('f1')}));

      expect(container.read(conversationProvider).entries, isEmpty);
    });

    test('testOutcomeFromFileStatusCoversAllValues', () {
      expect(ConversationReceiveRecorder.outcomeFromFileStatus(FileStatus.finished), ConversationFileOutcome.success);
      expect(ConversationReceiveRecorder.outcomeFromFileStatus(FileStatus.failed), ConversationFileOutcome.failure);
      expect(ConversationReceiveRecorder.outcomeFromFileStatus(FileStatus.skipped), ConversationFileOutcome.skipped);
      expect(ConversationReceiveRecorder.outcomeFromFileStatus(FileStatus.queue), ConversationFileOutcome.pending);
      expect(ConversationReceiveRecorder.outcomeFromFileStatus(FileStatus.sending), ConversationFileOutcome.pending);
    });
  });
}
