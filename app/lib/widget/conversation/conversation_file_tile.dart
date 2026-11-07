import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/widget/file_thumbnail.dart';
import 'package:localsend_isolates/model/file_type.dart';

/// 会话中本地文件或 Android content URI 的图片预览。
class ConversationFileThumb extends StatelessWidget {
  final ConversationFileSummary file;

  /// 图片预览的最大边长。
  final double size;

  const ConversationFileThumb({super.key, required this.file, this.size = 220});

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

    final ImageProvider<Object> provider = path.startsWith('content://') ? ContentUriImage(Uri.parse(path)) : FileImage(File(path));
    Widget failed({Color? color}) => SizedBox(
      width: size,
      height: 80,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined, color: color),
          Text(
            t.dialogs.cannotOpenFile.title,
            textAlign: TextAlign.center,
            style: TextStyle(color: color),
          ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => Navigator.of(context, rootNavigator: true).push<void>(
          MaterialPageRoute(
            builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light,
              child: Scaffold(
                backgroundColor: Colors.black,
                body: CallbackShortcuts(
                  bindings: {const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.of(context).maybePop()},
                  child: Focus(
                    autofocus: true,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          maxScale: 4,
                          child: Image(
                            image: ResizeImage(provider, width: 2048, height: 2048, policy: ResizeImagePolicy.fit),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => failed(color: Colors.white),
                          ),
                        ),
                        SafeArea(
                          child: Align(
                            alignment: AlignmentDirectional.topStart,
                            child: BackButton(
                              style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: Image(
          image: ResizeImage.resizeIfNeeded(
            (size * MediaQuery.devicePixelRatioOf(context)).round(),
            null,
            provider,
          ),
          width: size,
          height: size,
          fit: BoxFit.contain,
          // 文件缺失/不可读时静默回退到图片图标（离线、清理后、path 失效等场景）
          errorBuilder: (context, error, stackTrace) => failed(),
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
