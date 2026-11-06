import 'package:localsend_app/provider/conversation_ui_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:test/test.dart';

/// P2 会话 UI 状态测试：选中、窄屏详情、按 peerKey 草稿。
/// 对应验收：切设备不丢草稿、返回列表不丢选中（方案 6.2/6.3、不变量 1）。
void main() {
  group('选中与详情', () {
    test('selectPeer 设置选中并进入窄屏详情', () {
      final service = Notifier.test(notifier: ConversationUiService());

      service.notifier.selectPeer('fp:aaa');

      expect(service.state.selectedPeerKey, 'fp:aaa');
      expect(service.state.showDetailOnMobile, true);
    });

    test('backToList 只收起详情，保留选中设备（宽度切换不丢选中）', () {
      final service = Notifier.test(notifier: ConversationUiService());

      service.notifier.selectPeer('fp:aaa');
      service.notifier.backToList();

      expect(service.state.selectedPeerKey, 'fp:aaa');
      expect(service.state.showDetailOnMobile, false);
    });

    test('切换选中设备不影响其他状态字段', () {
      final service = Notifier.test(notifier: ConversationUiService());

      service.notifier.selectPeer('fp:aaa');
      service.notifier.updateDraft('fp:aaa', 'draft for aaa');
      service.notifier.selectPeer('fp:bbb');

      expect(service.state.selectedPeerKey, 'fp:bbb');
      // 切设备不丢原设备草稿（方案 9.1）
      expect(service.state.drafts['fp:aaa'], 'draft for aaa');
    });
  });

  group('按 peerKey 的纯文字草稿', () {
    test('草稿按设备隔离保存', () {
      final service = Notifier.test(notifier: ConversationUiService());

      service.notifier.updateDraft('fp:aaa', 'hello aaa');
      service.notifier.updateDraft('fp:bbb', 'hello bbb');

      expect(service.state.drafts, {'fp:aaa': 'hello aaa', 'fp:bbb': 'hello bbb'});
    });

    test('文字原样保存：不 trim、保留换行（方案 6.2）', () {
      final service = Notifier.test(notifier: ConversationUiService());

      service.notifier.updateDraft('fp:aaa', '  line1\nline2  \n');

      expect(service.state.drafts['fp:aaa'], '  line1\nline2  \n');
    });

    test('空文本等价于删除草稿键', () {
      final service = Notifier.test(notifier: ConversationUiService());

      service.notifier.updateDraft('fp:aaa', 'typing');
      service.notifier.updateDraft('fp:aaa', '');

      expect(service.state.drafts.containsKey('fp:aaa'), false);
    });

    test('clearDraft 只清目标设备，其他设备草稿保留', () {
      final service = Notifier.test(notifier: ConversationUiService());
      service.notifier.updateDraft('fp:aaa', 'a');
      service.notifier.updateDraft('fp:bbb', 'b');

      service.notifier.clearDraft('fp:aaa');

      expect(service.state.drafts, {'fp:bbb': 'b'});
    });

    test('clearDraft 对不存在的草稿是无操作（不产生新状态对象）', () {
      final service = Notifier.test(notifier: ConversationUiService());
      final before = service.state;

      service.notifier.clearDraft('fp:unknown');

      expect(identical(service.state, before), true);
    });
  });
}
