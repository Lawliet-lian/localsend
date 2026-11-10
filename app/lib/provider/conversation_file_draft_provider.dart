import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/native/conversation_attachment_cache.dart';
import 'package:refena_flutter/refena_flutter.dart';

final conversationFileDraftProvider = NotifierProvider<ConversationFileDraftService, Map<String, List<CrossFile>>>((ref) {
  return ConversationFileDraftService();
});

class ConversationFileDraftService extends Notifier<Map<String, List<CrossFile>>> {
  final _caches = <String, ConversationAttachmentCache>{};

  void addPicked(String peerKey, List<CrossFile> files, ConversationAttachmentCache cache) {
    if (files.isEmpty) {
      cache.close();
      return;
    }
    (_caches[peerKey] ??= ConversationAttachmentCache()).retain(cache);
    setFiles(peerKey, [...?state[peerKey], ...files]);
  }

  ConversationAttachmentCache? takeCache(String peerKey) => _caches.remove(peerKey);
  @override
  Map<String, List<CrossFile>> init() => {};

  void setFiles(String peerKey, List<CrossFile> files) {
    final next = Map<String, List<CrossFile>>.of(state);
    if (files.isEmpty) {
      _caches.remove(peerKey)?.close();
      next.remove(peerKey);
    } else {
      next[peerKey] = List.unmodifiable(files);
    }
    state = next;
  }
}
