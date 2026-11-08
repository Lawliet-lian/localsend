import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';

import 'package:localsend_app/model/cross_file.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _logger = Logger('ConversationAttachmentCache');

/// Owns the copies needed by one transfer, including any in-flight retry.
class ConversationAttachmentCache {
  Directory? _directory;
  int _readers = 0;
  bool _closed = false;

  final List<Uint8List> _bookmarks = [];

  bool get hasFiles => _directory != null || _bookmarks.isNotEmpty;

  Future<void> holdBookmark(Uint8List bookmark) async {
    if (await DesktopDrop.instance.startAccessingSecurityScopedResource(bookmark: bookmark)) {
      _bookmarks.add(bookmark);
    } else {
      throw FileSystemException('Cannot access dropped item');
    }
  }

  Future<List<CrossFile>> stage(List<CrossFile> files, {required bool copyImportedFiles}) async {
    final temp = (await getTemporaryDirectory()).path;
    final staged = <CrossFile>[];
    for (final file in files) {
      final path = file.path;
      if (path == null || path.startsWith('content://') || (!copyImportedFiles && file.asset == null && !p.isWithin(temp, path))) {
        staged.add(file);
        continue;
      }

      // iOS's legacy picker clears the whole temporary directory. Keep these
      // copies under the application cache instead, in a directory per transfer.
      final directory = _directory ??= await (await getApplicationCacheDirectory()).createTemp('conversation-');
      final copy = await File(path).copy(p.join(directory.path, '${staged.length}'));
      staged.add(file.copyWith(path: copy.path));
    }
    return staged;
  }

  Future<void> use(Future<void> Function() operation) async {
    _readers++;
    try {
      await operation();
    } finally {
      _readers--;
      await _deleteIfUnused();
    }
  }

  void close() {
    _closed = true;
    unawaited(_deleteIfUnused());
  }

  Future<void> _deleteIfUnused() async {
    if (_closed && _readers == 0 && _bookmarks.isNotEmpty) {
      final bookmarks = List<Uint8List>.of(_bookmarks);
      _bookmarks.clear();
      for (final bookmark in bookmarks) {
        try {
          await DesktopDrop.instance.stopAccessingSecurityScopedResource(bookmark: bookmark);
        } catch (e) {
          _logger.warning('Could not release dropped item access', e);
        }
      }
    }
    final directory = _directory;
    if (_closed && _readers == 0 && directory != null) {
      _directory = null;
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        _logger.warning('Could not remove conversation attachment cache');
      }
    }
  }
}
