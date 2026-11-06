import 'dart:async';

import 'package:flutter/material.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';

final _logger = Logger('ConversationAttachment');

/// 会话附件「即选即发」的选择协调状态（P9b，方案 6.3）。
///
/// 第一版不做跨设备持久化附件草稿：picker 会写全局 selectedSendingFilesProvider，
/// 因此本 provider 只负责三件事——
/// 1. **门槛**：仅全局 selection 为空且无活跃发送时允许打开选择器；
/// 2. **picking 锁**：选择器打开期间锁住会话发送与设备切换（接线层读取本标志）；
/// 3. **编排**：选择结束后取不可变快照立即发起 conversation 发送，取消不产生空传输。
///
/// 缓存生命周期合同（方案 6.3 门槛）：**绝不 dispatch ClearSelectionAction**
/// （它会连带清缓存）。提交后沿用既有安全清理时机——send_provider 的 closeSession
/// 在 finished && sendMode.single 时自动清 selection；multiple 模式下 selection 保留，
/// 门槛会阻止下一次附件选择，用户仍可在旧 SendTab 手动清空（旧路径行为不变）。
class ConversationAttachmentState {
  /// 选择器是否正在打开（含 picker 弹层与文件转换期间）。
  /// 这是唯一的 UI 状态字段，不含文字正文/路径等敏感内容，默认 toString 即脱敏。
  final bool picking;

  const ConversationAttachmentState({this.picking = false});
}

final conversationAttachmentProvider = NotifierProvider<ConversationAttachmentService, ConversationAttachmentState>((ref) {
  return ConversationAttachmentService();
});

/// 附件按钮的响应式门槛投影：接线层 watch 它决定按钮是否可用。
///
/// 三个事实全部 select 成 bool，避免 selection 列表内容或 session 进度细节
/// 造成无谓重建；任一条件不满足即禁用（按钮仍可见，平台不支持的**选项**
/// 由 FilePickerOption.getOptionsForPlatform 在弹层内过滤，门槛与平台能力各司其职）。
final conversationAttachmentEnabledProvider = ViewProvider((ref) {
  final picking = ref.watch(conversationAttachmentProvider.select((s) => s.picking));
  final selectionEmpty = ref.watch(selectedSendingFilesProvider.select((files) => files.isEmpty));
  // 保守判定：sendProvider 中任何未 closeSession 的 session（含 finishedWithErrors
  // 等待用户关闭的）都算活跃发送——宁可少选一次，也不把选择混进未结束的旧任务。
  final noActiveSend = ref.watch(sendProvider.select((sessions) => sessions.isEmpty));
  return !picking && selectionEmpty && noActiveSend;
});

class ConversationAttachmentService extends Notifier<ConversationAttachmentState> {
  @override
  ConversationAttachmentState init() => const ConversationAttachmentState();

  /// 发起一次「即选即发」附件流程（P9b）。
  ///
  /// [target] 在调用时固定为当前选中的在线设备：picking 锁保证选择器期间
  /// 接线层忽略设备切换，因此快照一定发给打开选择器时的那台设备。
  ///
  /// [pick] 仅供测试注入选择器行为（真实实现依赖原生 picker/平台通道，
  /// 无法纯 Dart 运行）；生产默认走 AddFileDialog.open——复用现有
  /// FilePickerOption/PickFileAction 平台能力，不改原生 picker。
  /// AddFileDialog 结束后的 popUntilRoot 只关闭弹层：会话详情是内联渲染
  /// 而非路由，不会被收起（方案 6.1 单栏合同）。
  Future<void> pickAndSend(
    BuildContext context, {
    required Device target,
    @visibleForTesting Future<void> Function()? pick,
  }) async {
    // 双保险：按钮禁用是第一道，dispatch 时再核一次门槛（防并发点击/状态竞态）
    if (state.picking || ref.read(selectedSendingFilesProvider).isNotEmpty || ref.read(sendProvider).isNotEmpty) {
      return;
    }

    state = const ConversationAttachmentState(picking: true);
    try {
      // 选择器打开期间 picking=true：接线层据此锁发送与切设备（方案 6.3）
      await (pick ?? () => AddFileDialog.open(context: context, options: FilePickerOption.getOptionsForPlatform()))();

      // 不可变快照（方案 6.3）：picker 把结果写进全局 selection，这里复制成
      // 独立 unmodifiable 列表再交给 startSession——发送中任何后续选择
      // （AddFilesAction 产生新 state 列表）都不会混进本次任务。
      final files = List<CrossFile>.unmodifiable(ref.read(selectedSendingFilesProvider));
      if (files.isEmpty) {
        // 用户取消选择：不产生空传输，也不动 selection/缓存
        return;
      }

      // 不 await：锁只覆盖选择器期间，不把整个 session 时长当成 UI 阻塞
      // （与 P6c 文字发送一致）；状态演进由 P6b 记录器写入气泡。
      // 清理时机沿用 closeSession 的既有逻辑，本批不额外 dispatch ClearSelectionAction。
      unawaited(
        ref
            .notifier(sendProvider)
            .startSession(
              target: target,
              files: files,
              background: true,
              presentation: TransferPresentation.conversation,
            ),
      );
    } catch (e) {
      // picker 异常（权限/平台通道失败等）：吞掉并记日志——接线层以 unawaited
      // 调用本方法，抛出会变成未处理异步异常；既有 PickFileAction 分支内部
      // 已自行弹 NoPermissionDialog，这里不重复弹窗。
      _logger.warning('Failed to pick and send attachment', e);
    } finally {
      // 无论选择成功、取消还是 picker 异常，锁都必须释放
      state = const ConversationAttachmentState(picking: false);
    }
  }
}
