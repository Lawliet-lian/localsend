import 'dart:typed_data';

import 'package:refena_flutter/refena_flutter.dart';

final conversationImageDraftProvider = NotifierProvider<ConversationImageDraftService, Map<String, Uint8List>>((ref) {
  return ConversationImageDraftService();
});

class ConversationImageDraftService extends Notifier<Map<String, Uint8List>> {
  @override
  Map<String, Uint8List> init() => {};

  void setImage(String peerKey, Uint8List? image) {
    final next = Map<String, Uint8List>.of(state);
    if (image == null) {
      next.remove(peerKey);
    } else {
      next[peerKey] = image;
    }
    state = next;
  }
}
