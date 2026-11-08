import 'package:localsend_app/model/persistence/quick_save_mode.dart';

bool shouldAutoAcceptDevice({
  required QuickSaveMode mode,
  required bool encrypted,
  required String? certFingerprint,
  required String reportedFingerprint,
  required bool trustUnencryptedFavorites,
  required Iterable<String> favorites,
}) {
  if (mode == QuickSaveMode.on) return true;
  if (mode == QuickSaveMode.off) return false;
  final fingerprint = encrypted ? certFingerprint : (trustUnencryptedFavorites ? reportedFingerprint : null);
  return fingerprint != null && favorites.contains(fingerprint);
}
