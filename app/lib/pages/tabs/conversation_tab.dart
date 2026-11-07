import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/model/conversation/conversation_receive_card_vm.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/conversation_attachment_provider.dart';
import 'package:localsend_app/provider/conversation_provider.dart';
import 'package:localsend_app/provider/conversation_ui_provider.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/provider/file_transfer_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/network/server/server_provider.dart';
import 'package:localsend_app/provider/transfer_presentation_provider.dart';
import 'package:localsend_app/widget/conversation/conversation_panel.dart';
import 'package:localsend_app/widget/dialogs/conversation_clear_dialog.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 会话内接收卡片的投影 provider（P7c）：合并 serverProvider 的活跃 session、
/// P7a 固定的 presentation 映射与 fileTransferProvider 的实时进度读取。
///
/// 独立成顶层 provider 是为了可测试（widget 测试可直接 override 注入卡片），
/// 不模仿真实 ServerService 状态；判定逻辑本身在纯函数
/// [conversationReceiveCardEligible]（已单测覆盖）。
final conversationReceiveCardProvider = ViewProvider((ref) {
  final session = ref.watch(serverProvider.select((state) => state?.session));
  if (session == null) {
    return null;
  }
  final presentation = ref.watch(transferPresentationProvider.select((p) => p[session.sessionId] ?? TransferPresentation.legacy));
  if (!conversationReceiveCardEligible(session: session, presentation: presentation)) {
    return null;
  }
  // watch 进度源：sending 时逐文件进度事件重建本 provider → 新 vm → 卡片刷新
  // （卡片自身不订阅 provider，避免在面板子树内直接 watch ChangeNotifierProvider）
  ref.watch(fileTransferProvider);
  return ConversationReceiveCardVm(
    session: session,
    progressOf: (fileId) => ref.read(fileTransferProvider).getProgress(sessionId: session.sessionId, fileId: fileId),
  );
});

/// "会话"入口 tab（方案 6.1）：把 P3 显示投影与 P2 UI 状态接线到 P4 面板，
/// 并提供 P6c 纯文字发送与 P7c 接收卡片。
///
/// 本文件只做接线：watch + 回调转发 + 消息 CrossFile 构造（沿用 AddMessageAction
/// 的协议格式：单 text 文件 + UTF8 bytes，发送侧在 startSession 内嵌 preview）；
/// 接收卡片按钮全部转发 serverProvider 同名动作，传输控制仍归属原有 provider；
/// 旧入口（接收/发送/设置）行为完全不变，会话 tab 追加在首页 enum 末尾。
class ConversationTab extends StatelessWidget {
  const ConversationTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    // 显示投影：附近设备 + 历史 + 活跃收发合并后的只读视图列表
    final views = context.watch(conversationPeerViewsProvider);
    // 记录全集由面板按选中 peerKey 过滤
    final entries = context.watch(conversationProvider.select((state) => state.entries));
    final ui = context.watch(conversationUiProvider);

    // picking 标志用于选择器打开期间锁住附件、文字发送与设备切换。
    final attachmentEnabled = context.watch(conversationAttachmentEnabledProvider);
    final picking = context.watch(conversationAttachmentProvider.select((s) => s.picking));
    final selectedDevice = views.firstWhereOrNull((v) => v.peerKey == ui.selectedPeerKey)?.device;

    // P7c 接收卡片：投影层已按 eligibility 判定；卡片内部自行订阅进度（不高频重建本 tab）
    final cardVm = context.watch(conversationReceiveCardProvider);
    // 卡片只属于对端设备：未选中/选中别人时不展示（列表角标 hasActiveReceive 负责提醒）
    final showCardForSelected = conversationReceiveCardForPeer(
      vm: cardVm,
      selectedPeerKey: ui.selectedPeerKey,
      peerKeyFor: ConversationPeer.peerKeyFor,
    );

    return ConversationPanel(
      views: views,
      entries: entries,
      selectedPeerKey: ui.selectedPeerKey,
      showDetailOnNarrow: ui.showDetailOnMobile,
      onSelect: (peerKey) {
        // P9b：选择器打开期间锁住设备切换（含窄屏返回列表），
        // 保证附件快照一定发给打开选择器时选中的设备
        if (picking) {
          return;
        }
        if (peerKey == null) {
          // 窄屏返回列表：只收起详情，保留选中高亮与草稿（conversationUiProvider 语义）
          ref.notifier(conversationUiProvider).backToList();
        } else {
          ref.notifier(conversationUiProvider).selectPeer(peerKey);
        }
      },
      draftText: ui.selectedPeerKey == null ? '' : ui.drafts[ui.selectedPeerKey] ?? '',
      onDraftChanged: (text) {
        final peerKey = ui.selectedPeerKey;
        if (peerKey != null) {
          // 草稿按 peerKey 保存，不碰全局 selectedSendingFilesProvider（方案 6.3）
          ref.notifier(conversationUiProvider).updateDraft(peerKey, text);
        }
      },
      onSendText: (text) => _sendText(ref, views, ui.selectedPeerKey, text),
      // P9b：附件即选即发——设备离线（device 为 null）时不传回调，按钮不出现；
      // 门槛/锁/快照/发送编排全部在协调 provider，本层只转发
      onPickAttachment: selectedDevice == null
          ? null
          : () => unawaited(ref.notifier(conversationAttachmentProvider).pickAndSend(context, target: selectedDevice)),
      attachmentEnabled: attachmentEnabled,
      sendingLocked: picking,
      // P7c：卡片与按钮回调全部转发 serverProvider 原有动作；重复点击安全：
      // acceptFileRequest/declineFileRequest 内部已有 status != waiting 的 guard（门槛）
      receiveCard: showCardForSelected ? cardVm : null,
      onReceiveAccept: (fileNameMap) => ref.notifier(serverProvider).acceptFileRequest(fileNameMap),
      onReceiveDecline: () => ref.notifier(serverProvider).declineFileRequest(),
      onReceiveCancel: () => ref.notifier(serverProvider).cancelSession(),
      onReceiveClose: () => ref.notifier(serverProvider).closeSession(),
      // P9a-3：顶栏「清空当前会话」菜单只回调 peerKey，确认与落盘都在本接线层完成，面板保持 dumb
      onClearPeer: (peerKey) => _clearPeer(context, ref, views, peerKey),
    );
  }

  /// 发起一次会话内纯文字发送（P6c）：全程不离开会话容器。
  /// 文字原样编码：不 trim、不丢失换行（方案 6.2）。
  void _sendText(Ref ref, List<ConversationPeerView> views, String? peerKey, String text) {
    // P9b 双保险：选择器打开期间禁止文字发送（composer 已禁用，此处防竞态）
    if (ref.read(conversationAttachmentProvider).picking) {
      return;
    }
    final view = views.firstWhereOrNull((v) => v.peerKey == peerKey);
    final device = view?.device;
    // 无选中设备或设备不在线：绝不发送（输入栏已禁用，此处是接线层双保险）
    if (view == null || device == null || text.isEmpty) {
      return;
    }

    // 与 AddMessageAction 相同的消息协议格式（单 text 文件 + UTF8 bytes）
    final bytes = utf8.encode(text);
    final file = CrossFile(
      name: '${_uuid.v4()}.txt',
      fileType: FileType.text,
      size: bytes.length,
      thumbnail: null,
      asset: null,
      path: null,
      bytes: bytes,
      lastModified: null,
      lastAccessed: null,
    );

    // presentation = conversation：不开 SendPage/ProgressPage，记录由 P6b 接入点写入；
    // 不 await：发送全程不阻塞会话容器，状态演进由气泡展示
    unawaited(
      ref
          .notifier(sendProvider)
          .startSession(
            target: device,
            files: [file],
            background: true,
            presentation: TransferPresentation.conversation,
          ),
    );
    // 发送已提交：清本设备草稿（不影响其他设备的草稿）
    ref.notifier(conversationUiProvider).clearDraft(view.peerKey);
  }

  /// 清空当前会话（P9a-3）：复用 P9a-2 的通用确认对话框 [ConversationClearDialog]，
  /// 仅把文案换成「按设备」版本（t.conversation.clearPeerDialog，带对端别名插值）。
  /// 门槛（方案第 7 节 / 不变量 2）：只清除该 peer 的会话记录，保留设备展示信息，
  /// 不删除真实文件、不取消进行中的传输；关闭保存时清除仍会落盘删除
  /// （ClearPeerEntriesAction 的 after 已 schedulePersist，并在 reduce 里 forgetNewEntryGuard）。
  void _clearPeer(BuildContext context, Ref ref, List<ConversationPeerView> views, String peerKey) async {
    final alias = views.firstWhereOrNull((v) => v.peerKey == peerKey)?.alias ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ConversationClearDialog(
        title: t.conversation.clearPeerDialog.title,
        // clearPeerDialog 是嵌套对象（title + 带 {name} 插值的 content），必须取 content 调用
        content: t.conversation.clearPeerDialog.content(name: alias),
      ),
    );
    if (confirmed == true) {
      ref.redux(conversationProvider).dispatch(ClearPeerEntriesAction(peerKey));
    }
  }
}
