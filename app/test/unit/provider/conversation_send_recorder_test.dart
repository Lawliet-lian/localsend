import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/state/send/send_session_state.dart';
import 'package:localsend_app/model/state/send/sending_file.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/conversation_send_recorder.dart';
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

/// P6b：发送会话记录器的单元测试。
/// 记录器是 send_provider 全部接入点的实际执行者；startSession 整体流程依赖
/// Rust/isolate 无法纯 Dart 集成（P0 已核实），故在此层验证记录合同。
void main() {
  const sessionId = 'session-1';
  const entryId = 'send:session-1'; // ConversationEntry.buildEntryId(send, sessionId)

  late RefenaContainer container;
  late ConversationSendRecorder recorder;

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

  List<({String id, CrossFile file})> selectedFiles() {
    return [
      (
        id: 'f1',
        file: CrossFile(
          name: 'note.txt',
          fileType: FileType.text,
          size: 100,
          thumbnail: null,
          asset: null,
          path: '/tmp/note.txt',
          bytes: null,
          lastModified: null,
          lastAccessed: null,
        ),
      ),
      (
        id: 'f2',
        file: CrossFile(
          name: 'photo.png',
          fileType: FileType.image,
          size: 2048,
          thumbnail: null,
          asset: null,
          path: '/tmp/photo.png',
          bytes: null,
          lastModified: null,
          lastAccessed: null,
        ),
      ),
    ];
  }

  SendingFile sendingFile(String id, {String? token, String? error, String? preview}) {
    return SendingFile(
      file: FileDto(
        id: id,
        fileName: '$id.bin',
        size: 10,
        fileType: FileType.other,
        hash: null,
        preview: preview,
        metadata: null,
      ),
      token: token,
      thumbnail: null,
      asset: null,
      path: null,
      bytes: null,
      errorMessage: error,
    );
  }

  SendSessionState session(Map<String, SendingFile> files, {String? errorMessage}) {
    return SendSessionState(
      sessionId: sessionId,
      remoteSessionId: 'remote-1',
      background: true,
      status: SessionStatus.sending,
      target: target(),
      files: files,
      hashedFileCount: files.length,
      startTime: null,
      endTime: null,
      sendingTasks: [],
      errorMessage: errorMessage,
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
    recorder = ConversationSendRecorder(container);
  });

  tearDown(() {
    container.disposeContainer();
  });

  /// 把 session 标记为会话展示模式（模拟 startSession 的 presentation 记录）
  void markConversation() {
    container.notifier(transferPresentationProvider).set(sessionId, TransferPresentation.conversation);
  }

  group('ConversationSendRecorder', () {
    test('an empty attachment acceptance records skipped files and survives serialization', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());
      recorder.onEmptyAcceptance(sessionId: sessionId, files: {'f1': sendingFile('f1'), 'f2': sendingFile('f2')});

      final snapshot = ConversationEntryMapper.deserialize(entry()!.serialize());
      expect(snapshot.outcome, ConversationOutcome.noFilesAccepted);
      expect(snapshot.files.map((file) => file.outcome), [ConversationFileOutcome.skipped, ConversationFileOutcome.skipped]);
    });

    test('an empty acceptance confirms a text preview', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: [], text: 'hello');
      recorder.onEmptyAcceptance(
        sessionId: sessionId,
        files: {'f1': sendingFile('f1', preview: 'hello')},
      );

      expect(entry()!.outcome, ConversationOutcome.finished);
      expect(entry()!.files, isEmpty);
    });

    test('testLegacySessionProducesNoRecords', () {
      // 门槛：旧 legacy 路径不产生任何会话记录（未记录 presentation = legacy）
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.waiting);
      recorder.onTransferring(
        sessionId: sessionId,
        files: {'f1': sendingFile('f1', token: 't')},
      );
      recorder.onTransferSnapshot(
        session: session({'f1': sendingFile('f1', token: 't')}),
        outcome: ConversationOutcome.finished,
      );

      expect(container.read(conversationProvider).entries, isEmpty);
      expect(container.read(conversationProvider).peers, isEmpty);
    });

    test('testOnSessionCreatedRegistersPreparingEntry', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());

      final e = entry()!;
      // 设备信息：稳定 peerKey（fp: 小写指纹）
      expect(e.peerKey, 'fp:aa:bb');
      expect(e.direction, ConversationDirection.send);
      expect(e.localSessionId, sessionId);
      expect(e.kind, ConversationEntryKind.file);
      expect(e.outcome, ConversationOutcome.preparing);
      expect(e.finishedAt, isNull);
      // 文件摘要只有展示字段，初始全部 pending
      expect(e.files.map((f) => (f.fileId, f.fileName, f.size, f.outcome)).toList(), [
        ('f1', 'note.txt', 100, ConversationFileOutcome.pending),
        ('f2', 'photo.png', 2048, ConversationFileOutcome.pending),
      ]);
      expect(container.read(conversationProvider).peers.single.fingerprint, 'AA:BB');
    });

    test('testUpdateIsIdempotentUpsert', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());

      // 重复阶段更新只原位替换，不追加新气泡（不变量 10）
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.waiting);
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.waiting);
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.transferring);

      expect(container.read(conversationProvider).entries.length, 1);
      final e = entry()!;
      expect(e.outcome, ConversationOutcome.transferring);
      expect(e.finishedAt, isNull);
      // 未提供 replaceFiles 时保留原文件摘要
      expect(e.files.length, 2);
    });

    test('testTerminalOutcomeStampsFinishedAt', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.finished);

      final e = entry()!;
      expect(e.outcome, ConversationOutcome.finished);
      expect(e.finishedAt, isNotNull);
      expect(e.finishedAt!.isUtc, isTrue);
    });

    test('testTransferringMarksUnacceptedFilesSkipped', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());

      // f1 被接受（有 token），f2 未被选择（无 token）
      recorder.onTransferring(
        sessionId: sessionId,
        files: {
          'f1': sendingFile('f1', token: 'tok-1'),
          'f2': sendingFile('f2'),
        },
      );

      final e = entry()!;
      expect(e.outcome, ConversationOutcome.transferring);
      expect(e.files.firstWhere((f) => f.fileId == 'f1').outcome, ConversationFileOutcome.pending);
      expect(e.files.firstWhere((f) => f.fileId == 'f2').outcome, ConversationFileOutcome.skipped);
    });

    test('testTerminalSnapshotConvertsLiveFileStatuses', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());

      final transfer = container.read(fileTransferProvider);
      transfer.setStatus(sessionId: sessionId, fileId: 'ok', status: FileStatus.finished);
      transfer.setStatus(sessionId: sessionId, fileId: 'bad', status: FileStatus.failed);
      transfer.setStatus(sessionId: sessionId, fileId: 'skipped', status: FileStatus.skipped);
      transfer.setStatus(sessionId: sessionId, fileId: 'queued', status: FileStatus.queue);

      final snapshotSession = session({
        'ok': sendingFile('ok', token: 't'),
        'bad': sendingFile('bad', token: 't', error: 'read failed'),
        'skipped': sendingFile('skipped'),
        'queued': sendingFile('queued', token: 't'),
      }, errorMessage: 'partial network error');

      recorder.onTransferSnapshot(session: snapshotSession, outcome: ConversationOutcome.partialFailure);

      final e = entry()!;
      expect(e.outcome, ConversationOutcome.partialFailure);
      expect(e.error, 'partial network error');
      expect(e.finishedAt, isNotNull);
      expect(e.files.firstWhere((f) => f.fileId == 'ok').outcome, ConversationFileOutcome.success);
      expect(e.files.firstWhere((f) => f.fileId == 'bad').outcome, ConversationFileOutcome.failure);
      expect(e.files.firstWhere((f) => f.fileId == 'bad').error, 'read failed');
      expect(e.files.firstWhere((f) => f.fileId == 'skipped').outcome, ConversationFileOutcome.skipped);
      expect(e.files.firstWhere((f) => f.fileId == 'queued').outcome, ConversationFileOutcome.pending);
    });

    test('testClearedEntryIsNotRevived', () {
      markConversation();
      recorder.onSessionCreated(sessionId: sessionId, target: target(), selectedFiles: selectedFiles());

      // 用户清除记录后，晚到的完成事件不得补回（不变量 10 / tombstone）
      container.redux(conversationProvider).dispatch(RemoveConversationEntryAction(entryId));
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.finished);

      expect(container.read(conversationProvider).entries, isEmpty);
    });

    test('testUpdateWithoutRegisteredEntryIsNoop', () {
      markConversation();
      // 未登记直接 update（如 PIN 取消发生在 ensure 之前的防御场景）：不应凭空造记录
      recorder.update(sessionId: sessionId, outcome: ConversationOutcome.canceledBySender);

      expect(container.read(conversationProvider).entries, isEmpty);
    });

    test('testOutcomeFromFileStatusCoversAllValues', () {
      // 纯转换函数覆盖 FileStatus 全部取值
      expect(ConversationSendRecorder.outcomeFromFileStatus(FileStatus.finished), ConversationFileOutcome.success);
      expect(ConversationSendRecorder.outcomeFromFileStatus(FileStatus.failed), ConversationFileOutcome.failure);
      expect(ConversationSendRecorder.outcomeFromFileStatus(FileStatus.skipped), ConversationFileOutcome.skipped);
      expect(ConversationSendRecorder.outcomeFromFileStatus(FileStatus.queue), ConversationFileOutcome.pending);
      expect(ConversationSendRecorder.outcomeFromFileStatus(FileStatus.sending), ConversationFileOutcome.pending);
    });

    test('testTextSessionRegistersKindTextVerbatim', () {
      markConversation();
      // P6c：纯文字会话——kind=text，正文原样保存（前导空格与换行不丢），文件摘要置空
      recorder.onSessionCreated(
        sessionId: sessionId,
        target: target(),
        selectedFiles: selectedFiles(),
        text: '  line1\nline2  ',
      );

      final e = entry()!;
      expect(e.kind, ConversationEntryKind.text);
      expect(e.text, '  line1\nline2  ');
      expect(e.files, isEmpty);
    });

    test('testExtractMessageTextMatchesProtocolCondition', () {
      final message = CrossFile(
        name: 'm.txt',
        fileType: FileType.text,
        size: 4,
        thumbnail: null,
        asset: null,
        path: null,
        bytes: utf8.encode('a\n b'),
        lastModified: null,
        lastAccessed: null,
      );
      final image = CrossFile(
        name: 'p.png',
        fileType: FileType.image,
        size: 9,
        thumbnail: null,
        asset: null,
        path: null,
        bytes: null,
        lastModified: null,
        lastAccessed: null,
      );

      // 单 text + bytes → 原文（与 startSession 内嵌 preview 的协议判断一致）
      expect(ConversationSendRecorder.extractMessageText([message]), 'a\n b');
      // 文件会话/多文件/无 bytes → null（按文件记录）
      expect(ConversationSendRecorder.extractMessageText([image]), isNull);
      expect(ConversationSendRecorder.extractMessageText([message, message]), isNull);
      expect(ConversationSendRecorder.extractMessageText([]), isNull);
    });
  });
}
