import 'package:localsend_app/model/cross_file.dart';
import 'package:refena_flutter/refena_flutter.dart';

final conversationFileDraftProvider = NotifierProvider<ConversationFileDraftService, Map<String, List<CrossFile>>>((ref) {
  return ConversationFileDraftService();
});

class ConversationFileDraftService extends Notifier<Map<String, List<CrossFile>>> {
  @override
  Map<String, List<CrossFile>> init() => {};

  void setFiles(String peerKey, List<CrossFile> files) {
    final next = Map<String, List<CrossFile>>.of(state);
    if (files.isEmpty) {
      next.remove(peerKey);
    } else {
      next[peerKey] = List.unmodifiable(files);
    }
    state = next;
  }
}
