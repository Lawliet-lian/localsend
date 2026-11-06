import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/conversation_receive_card_vm.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/state/server/receive_session_state.dart';
import 'package:localsend_app/model/state/server/receiving_file.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/dto/file_dto.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:localsend_isolates/model/session_status.dart';

/// P7c：接收卡片投影层的纯函数测试（方案 9.1：不启动 Rust/isolate 即可覆盖判定合同）。
void main() {
  Device sender({String fingerprint = 'AA:BB'}) {
    return Device(
      signalingId: null,
      ip: '10.0.0.1',
      version: '2.1',
      port: 53317,
      https: true,
      fingerprint: fingerprint,
      alias: 'Alias',
      deviceModel: 'model',
      deviceType: DeviceType.mobile,
      download: false,
      channels: const [],
    );
  }

  ReceivingFile file(
    String id, {
    int size = 10,
    String? desiredName,
    FileType fileType = FileType.image,
    String? preview,
  }) {
    return ReceivingFile(
      file: FileDto(
        id: id,
        fileName: '$id.bin',
        size: size,
        fileType: fileType,
        hash: null,
        preview: preview,
        metadata: null,
      ),
      token: null,
      desiredName: desiredName,
      path: null,
      savedToGallery: false,
      errorMessage: null,
    );
  }

  ReceiveSessionState session(
    Map<String, ReceivingFile> files, {
    SessionStatus status = SessionStatus.waiting,
  }) {
    return ReceiveSessionState(
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
    );
  }

  ConversationReceiveCardVm vm(
    Map<String, ReceivingFile> files, {
    SessionStatus status = SessionStatus.waiting,
    double Function(String fileId)? progressOf,
  }) {
    final s = session(files, status: status);
    return ConversationReceiveCardVm(session: s, progressOf: progressOf ?? (_) => 0);
  }

  group('conversationReceiveCardEligible', () {
    test('无 session 或 legacy presentation：不建卡片（legacy 走旧 ReceivePage，会话内无双按钮）', () {
      expect(conversationReceiveCardEligible(session: null, presentation: TransferPresentation.conversation), isFalse);
      expect(conversationReceiveCardEligible(session: session({'a': file('a')}), presentation: TransferPresentation.legacy), isFalse);
    });

    test('conversation 且 waiting/sending/canceledBySender 均可见；终态不可见（不展示残留）', () {
      final s = {'a': file('a')};
      expect(conversationReceiveCardEligible(session: session(s), presentation: TransferPresentation.conversation), isTrue);
      expect(
        conversationReceiveCardEligible(
          session: session(s, status: SessionStatus.sending),
          presentation: TransferPresentation.conversation,
        ),
        isTrue,
      );
      expect(
        conversationReceiveCardEligible(
          session: session(s, status: SessionStatus.canceledBySender),
          presentation: TransferPresentation.conversation,
        ),
        isTrue,
      );
      for (final done in {
        SessionStatus.finished,
        SessionStatus.finishedWithErrors,
        SessionStatus.declined,
        SessionStatus.canceledByReceiver,
        SessionStatus.recipientBusy,
        SessionStatus.tooManyAttempts,
      }) {
        expect(
          conversationReceiveCardEligible(
            session: session(s, status: done),
            presentation: TransferPresentation.conversation,
          ),
          isFalse,
          reason: '终态 $done 不应展示卡片',
        );
      }
    });

    test('消息请求不建卡片（已被自动确认写气泡，waiting 只是旧页面等关闭）', () {
      // 单 text 文件 + preview 非空 = session.message 判定命中（与协议条件一致）
      final messageSession = session({'m': file('m', fileType: FileType.text, preview: 'hello')});
      expect(conversationReceiveCardEligible(session: messageSession, presentation: TransferPresentation.conversation), isFalse);
    });
  });

  group('ConversationReceiveCardVm', () {
    test('allFileNameMap：默认全选，desiredName 优先作固化名', () {
      final card = vm({
        'a': file('a', desiredName: 'renamed.txt'),
        'b': file('b'),
      });
      expect(card.allFileNameMap, {'a': 'renamed.txt', 'b': 'b.bin'});
    });

    test('totalProgress：按字节加权；零大小集合安全返回 0', () {
      final card = vm(
        {
          'a': file('a', size: 30),
          'b': file('b', size: 70),
        },
        progressOf: (id) => id == 'a' ? 1.0 : 0.0, // 30/100
      );
      expect(card.totalProgress, closeTo(0.3, 1e-9));

      final empty = vm({
        'z': file('z', size: 0),
      });
      expect(empty.totalProgress, 0);
    });
  });

  group('conversationReceiveCardForPeer', () {
    test('仅当 session 对端指纹规范化后等于选中 peerKey 才展示', () {
      final card = vm({'a': file('a')});
      // 与 ConversationPeer.peerKeyFor 相同的解析函数注入（大小写规范化由实现方负责）
      String normalize(String fp) => 'fp:${fp.toLowerCase()}';
      expect(conversationReceiveCardForPeer(vm: card, selectedPeerKey: 'fp:aa:bb', peerKeyFor: normalize), isTrue);
      expect(conversationReceiveCardForPeer(vm: card, selectedPeerKey: 'fp:other', peerKeyFor: normalize), isFalse);
      expect(conversationReceiveCardForPeer(vm: card, selectedPeerKey: null, peerKeyFor: normalize), isFalse);
      expect(conversationReceiveCardForPeer(vm: null, selectedPeerKey: 'fp:aa:bb', peerKeyFor: normalize), isFalse);
    });
  });
}
