import 'dart:io';

import 'package:flutter/material.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_isolates/model/file_type.dart';

/// 会话文件气泡里的缩略图块（P10 本地缩略图预览）。
///
/// 设计边界（严格不碰 Rust/协议/isolate/依赖）：
/// - 仅当 [ConversationFileSummary] 是图片、且携带本地 [ConversationFileSummary.path] 时，
///   才用 Image.file 渲染缩略图；加载失败/文件缺失通过 errorBuilder 回退到类型图标，
///   绝不抛异常、不影响气泡其余部分；
/// - 视频的帧缩略需要解码插件（引入依赖，违背约束），故视频/其它类型一律保持图标呈现；
/// - 本 widget 纯展示、不订阅 provider、不做任何打开/预览动作（全屏预览属后续批次）。
class ConversationFileThumb extends StatelessWidget {
  final ConversationFileSummary file;

  /// 缩略图与图标的统一边长（正方形，嵌入文件行的 Row 里）。
  final double size;

  const ConversationFileThumb({super.key, required this.file, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = file.path;
    final showImageThumb = file.fileType == FileType.image && path != null && path.isNotEmpty;

    Widget icon() => Icon(
      _iconFor(file.fileType),
      size: size,
      color: _colorFor(theme, file.fileType),
    );

    if (!showImageThumb) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(child: icon()),
      );
    }

    // 图片缩略图：cacheWidth 限制解码内存，避免整张原图解码拖慢列表；圆角贴合气泡风格。
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        // 文件缺失/不可读时静默回退到图片图标（离线、清理后、path 失效等场景）
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(Icons.broken_image_outlined, size: size, color: theme.colorScheme.outline),
          ),
        ),
      ),
    );
  }

  /// 类型图标：与既有气泡展示保持一致的图标语义。
  static IconData _iconFor(FileType type) {
    switch (type) {
      case FileType.image:
        return Icons.image;
      case FileType.video:
        return Icons.video_file;
      case FileType.text:
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// 类型配色：仅用于图标态的轻微区分，图片因走缩略图不受影响。
  static Color _colorFor(ThemeData theme, FileType type) {
    switch (type) {
      case FileType.video:
        return theme.colorScheme.tertiary;
      case FileType.text:
        return theme.colorScheme.secondary;
      default:
        return theme.colorScheme.outline;
    }
  }
}
