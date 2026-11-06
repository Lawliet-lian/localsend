import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';

/// P7a：接收侧展示模式判定的行为合同测试。
/// 门槛：开关关闭（默认）时一切请求恒为 legacy——接收行为零变化；
/// 链接（web 上传页）接收永远 legacy，即使开关开启。
/// WebRTC 接收走 webrtc_receiver.dart 独立路径，不经过 receive_controller，
/// 因此天然不会进入本判定（方案 6.1：判定只来自现有请求路径，不猜测平台名）。
void main() {
  group('decideReceivePresentation', () {
    test('testDefaultOffIsAlwaysLegacy', () {
      // 开关关闭 + 原生 HTTP 请求：legacy（改造前的默认路径，零行为变化）
      expect(
        decideReceivePresentation(enabled: false, viaWebUpload: false),
        TransferPresentation.legacy,
      );
      // 开关关闭 + 链接请求：同样是 legacy
      expect(
        decideReceivePresentation(enabled: false, viaWebUpload: true),
        TransferPresentation.legacy,
      );
    });

    test('testEnabledNativeHttpRequestIsConversation', () {
      // 开关开启 + 原生 HTTP（非链接）接收：进入会话展示模式
      expect(
        decideReceivePresentation(enabled: true, viaWebUpload: false),
        TransferPresentation.conversation,
      );
    });

    test('testWebUploadStaysLegacyEvenWhenEnabled', () {
      // 链接上传页的请求即使开关开启也必须 legacy（方案 6.1：链接收发始终 legacy）
      expect(
        decideReceivePresentation(enabled: true, viaWebUpload: true),
        TransferPresentation.legacy,
      );
    });
  });

  group('shouldAutoAcceptFavoriteInConversation', () {
    test('testConversationFavoriteAutoAccepts', () {
      // 会话模式 + 发送方在本端收藏列表：自动接收（文件/文字均免确认）
      expect(
        shouldAutoAcceptFavoriteInConversation(presentation: TransferPresentation.conversation, isFavorite: true),
        true,
      );
    });

    test('testConversationNonFavoriteStaysManual', () {
      // 会话模式 + 未收藏：仍由会话卡片手动接受。
      // 这正是“双方互收藏才无障碍”的单向语义：对方没收藏我时，我发给对方仍需对方手动同意。
      expect(
        shouldAutoAcceptFavoriteInConversation(presentation: TransferPresentation.conversation, isFavorite: false),
        false,
      );
    });

    test('testLegacyNeverAutoAcceptsByThisRule', () {
      // legacy 展示模式不受本规则影响（收藏与否都不自动），保持改造前行为；
      // legacy 的自动接收仍由 quickSave/quickSaveFromFavorites 单独负责。
      expect(
        shouldAutoAcceptFavoriteInConversation(presentation: TransferPresentation.legacy, isFavorite: true),
        false,
      );
      expect(
        shouldAutoAcceptFavoriteInConversation(presentation: TransferPresentation.legacy, isFavorite: false),
        false,
      );
    });
  });
}
