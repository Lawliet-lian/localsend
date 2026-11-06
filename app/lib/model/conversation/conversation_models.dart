import 'package:dart_mappable/dart_mappable.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:uuid/uuid.dart';

part 'conversation_models.mapper.dart';

const _uuid = Uuid();

/// 会话记录层的纯数据合同（方案 D 第 5.2 节）。
///
/// 这里只描述"展示与历史"，不描述传输本身：
/// - 摘要不得持有 SendingFile/ReceivingFile 原对象，
///   不保存 bytes、缩略图二进制、PIN、token、证书、取消任务等任何资源引用。
/// - 时间统一使用 UTC，由 UI 层转换成本地时区后按日期分组。
/// - 展示终态使用独立枚举 [ConversationOutcome]，禁止复用共享的 SessionStatus，
///   避免协议/传输状态演进时隐式破坏历史记录的持久化格式。

/// 传输方向。设备身份之外的记录去重键的一部分（entryId = direction + localSessionId），
/// 保证同一 sessionId 恰好出现在收发双向时不会产生键冲突。
/// 序列化需要 @MappableEnum（与 isolate 层的 FileType/DeviceType 同样做法）。
@MappableEnum()
enum ConversationDirection {
  send,
  receive,
}

/// 条目的展示类别：文字气泡或文件卡片（一批文件放在同一条气泡内）。
@MappableEnum()
enum ConversationEntryKind {
  text,
  file,
}

/// 会话条目的展示终态/阶段（方案 5.2：覆盖准备、等待、传输、完成、部分失败、拒绝、忙碌、取消）。
///
/// 说明：
/// - 取消必须区分来源（本端取消 / 远端取消），对应第 4 节"先记录取消来源"的要求；
/// - [failed] 承载网络异常等非文件级的整体失败，不允许伪装成成功；
/// - [incomplete] 用于重启后仍未结束的记录（"上次传输未完成"），不可自动重新发送。
@MappableEnum()
enum ConversationOutcome {
  preparing, // 准备阶段（如校验和计算），此时还没有真实会话请求
  waiting, // 已发出/已收到请求，等待对方决定
  transferring, // 文件传输中
  finished, // 全部成功完成
  partialFailure, // 完成但部分文件失败（对应 finishedWithErrors）
  declined, // 被对方拒绝（403）
  busy, // 对方忙碌（409）
  tooManyAttempts, // PIN 尝试过多（429）
  canceledBySender, // 发送端主动取消（含 PIN 弹窗取消）
  canceledByReceiver, // 接收端取消
  failed, // 网络异常等其他失败
  incomplete, // 重启后未结束的历史记录
}

/// 单个文件的最终展示状态。与 isolate 层的 FileStatus 分离，
/// 保证持久化格式不随传输实现演进而变化。
@MappableEnum()
enum ConversationFileOutcome {
  pending, // 尚无结果（等待决定/传输中）
  skipped, // 未被对方接受（选择被跳过）
  success, // 成功
  failure, // 失败
}

/// 会话对端设备的展示信息（不含 IP：IP 是可变化的地址，alias 是可变化的展示名）。
///
/// 设备身份一律以非空 fingerprint 为准（第 4 节不变量 4/5/6）：
/// - [fingerprint] 可信且非空 → peerKey 由指纹派生，跨 IP 变化、跨改名保持稳定；
/// - 缺少可信身份 → 生成一次性临时 peerKey，[isStable] 为 false，
///   调用方不得将其与任何已有会话自动合并。
@MappableClass()
class ConversationPeer with ConversationPeerMappable {
  /// 稳定键：'fp:小写指纹'；临时键：'tmp:uuid'。
  final String peerKey;

  /// 设备指纹。null 或空串表示缺少可信身份（此时 [isStable] 为 false）。
  final String? fingerprint;

  /// 最近一次观察到的展示名称（可能随时间变化，仅作展示用）。
  final String alias;

  /// 设备类型，用于渲染图标。历史不持久化"在线"状态。
  final DeviceType deviceType;

  const ConversationPeer({
    required this.peerKey,
    required this.fingerprint,
    required this.alias,
    required this.deviceType,
  });

  /// 由非空指纹派生稳定 peerKey。指纹统一转小写，
  /// 避免 core 层的大写 hex 与其他来源的大小写差异导致同一设备分裂成两个会话。
  static String stablePeerKey(String fingerprint) {
    return 'fp:${fingerprint.toLowerCase()}';
  }

  /// 为缺少可信身份的对端生成一次性临时键。
  /// 每次调用都不同，因此临时会话之间、临时与稳定会话之间永远不会自动合并。
  static String temporaryPeerKey() {
    return 'tmp:${_uuid.v4()}';
  }

  /// 有可信指纹时使用稳定键，否则退回临时键。
  static String peerKeyFor(String? fingerprint) {
    final normalized = fingerprint?.trim();
    if (normalized == null || normalized.isEmpty) {
      return temporaryPeerKey();
    }
    return stablePeerKey(normalized);
  }

  /// 该 peer 是否具备可长期关联的可信身份。
  bool get isStable {
    final fp = fingerprint;
    return fp != null && fp.trim().isNotEmpty;
  }

  static const fromJson = ConversationPeerMapper.fromJson;
}

/// 一条已发生（或正在发生）的传输摘要，对应会话界面里的一条气泡。
///
/// 去重合同（第 4 节不变量 10）：同一传输的重复事件/进度更新必须按 [entryId] upsert
/// 原条目，禁止追加新气泡；再次发送是新 session，自然生成新记录。
@MappableClass()
class ConversationEntry with ConversationEntryMappable {
  /// 稳定去重键，见 [buildEntryId]。
  final String entryId;

  /// 所属会话（对端设备）的 peerKey。
  final String peerKey;

  final ConversationDirection direction;

  /// 本端（本机生成）的 sessionId。文字与文件、重试都归属于这一个 session。
  final String localSessionId;

  final ConversationEntryKind kind;

  final ConversationOutcome outcome;

  /// 创建时间（UTC）。
  final DateTime createdAt;

  /// 终态时间（UTC）；未结束为 null。
  final DateTime? finishedAt;

  /// 批量文件放在该气泡内；纯文字条目为空列表。
  final List<ConversationFileSummary> files;

  /// 文字内容（仅 kind == text）。发出时不 trim、不丢失换行。
  final String? text;

  /// 整体错误信息（脱敏后的简短描述），单文件错误放在文件摘要里。
  final String? error;

  const ConversationEntry({
    required this.entryId,
    required this.peerKey,
    required this.direction,
    required this.localSessionId,
    required this.kind,
    required this.outcome,
    required this.createdAt,
    required this.finishedAt,
    required this.files,
    required this.text,
    required this.error,
  });

  /// entryId = direction + localSessionId（方案 5.2 约定）。
  /// 方向前缀保证收发双向即使 localSessionId 相同也不会互相覆盖。
  static String buildEntryId(ConversationDirection direction, String localSessionId) {
    return '${direction.name}:$localSessionId';
  }

  static const fromJson = ConversationEntryMapper.fromJson;
}

/// 单个文件的展示摘要（最终状态 + 真实保存位置）。
///
/// 注意：[path] 只是"记录时的真实保存结果"，重启后文件可能已被移动或删除，
/// 打开前必须走现有的可访问性检查逻辑，不得假定可直接 File 操作（第 4 节不变量 12）。
@MappableClass()
class ConversationFileSummary with ConversationFileSummaryMappable {
  /// 传输内的文件 id（与 session 内的 fileId 对应，用于 upsert 单文件结果）。
  final String fileId;

  /// 展示文件名（接收侧为用户确认的目标名 desiredName）。
  final String fileName;

  final FileType fileType;

  final int size;

  final ConversationFileOutcome outcome;

  /// 最终保存路径（接收方向）；未落盘/不适用为 null。
  final String? path;

  /// 是否保存到相册（Android/iOS gallery 流程经缓存文件，此处仅记录结果）。
  final bool savedToGallery;

  /// 该文件的错误信息（无错误为 null）。
  final String? error;

  const ConversationFileSummary({
    required this.fileId,
    required this.fileName,
    required this.fileType,
    required this.size,
    required this.outcome,
    required this.path,
    required this.savedToGallery,
    required this.error,
  });

  static const fromJson = ConversationFileSummaryMapper.fromJson;
}
