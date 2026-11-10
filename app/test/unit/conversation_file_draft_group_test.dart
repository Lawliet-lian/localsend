import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/file_draft_group.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_isolates/model/file_type.dart';

void main() {
  CrossFile file(String name, String path) => CrossFile(
    name: name,
    fileType: FileType.other,
    size: 1,
    thumbnail: null,
    asset: null,
    path: path,
    bytes: null,
    lastModified: null,
    lastAccessed: null,
  );

  test('groups folder contents by actual root, keeping standalone files separate', () {
    final groups = groupFileDrafts([
      file('folder/a.txt', '/first/folder/a.txt'),
      file('plain.txt', '/first/plain.txt'),
      file('folder/sub/b.txt', '/first/folder/sub/b.txt'),
      file('folder/c.txt', '/second/folder/c.txt'),
    ]);
    expect(groups.map((group) => group.name), ['folder', 'plain.txt', 'folder']);
    expect(groups.map((group) => group.indices), [
      [0, 2],
      [1],
      [3],
    ]);
    expect(groups.map((group) => group.isFolder), [true, false, true]);
  });
}
