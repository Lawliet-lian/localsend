import 'package:localsend_app/model/cross_file.dart';
import 'package:path/path.dart' as p;

class FileDraftGroup {
  final String name;
  final bool isFolder;
  final List<int> indices;
  int size;

  FileDraftGroup({required this.name, required this.isFolder, required this.indices, required this.size});
}

/// Groups files produced by directory selection without merging distinct folders
/// that happen to have the same name.
List<FileDraftGroup> groupFileDrafts(List<CrossFile> files) {
  final groups = <FileDraftGroup>[];
  final folders = <String, FileDraftGroup>{};
  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final parts = file.name.split('/');
    if (parts.length > 1 && file.path != null) {
      var root = file.path!;
      for (var j = 1; j < parts.length; j++) {
        root = p.dirname(root);
      }
      final key = p.normalize(root);
      final group = folders.putIfAbsent(key, () {
        final group = FileDraftGroup(name: parts.first, isFolder: true, indices: [], size: 0);
        groups.add(group);
        return group;
      });
      group.indices.add(i);
      group.size += file.size;
    } else {
      groups.add(FileDraftGroup(name: file.name, isFolder: false, indices: [i], size: file.size));
    }
  }
  return groups;
}
