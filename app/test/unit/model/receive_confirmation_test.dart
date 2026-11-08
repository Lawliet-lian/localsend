import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/persistence/quick_save_mode.dart';
import 'package:localsend_app/model/receive_confirmation.dart';

void main() {
  bool accept(QuickSaveMode mode, {bool encrypted = true, String? certificate = 'favorite', bool trust = false}) {
    return shouldAutoAcceptDevice(
      mode: mode,
      encrypted: encrypted,
      certFingerprint: certificate,
      reportedFingerprint: 'favorite',
      trustUnencryptedFavorites: trust,
      favorites: ['favorite'],
    );
  }

  test('manual and all-device modes do not depend on sender identity', () {
    expect(accept(QuickSaveMode.off), isFalse);
    expect(accept(QuickSaveMode.on, encrypted: false), isTrue);
    expect(accept(QuickSaveMode.on, certificate: null), isTrue);
  });

  test('encrypted favorites require the actual certificate fingerprint', () {
    expect(accept(QuickSaveMode.paired), isTrue);
    expect(accept(QuickSaveMode.paired, certificate: null, trust: true), isFalse);
    expect(accept(QuickSaveMode.paired, certificate: 'other', trust: true), isFalse);
  });

  test('unencrypted favorites require explicit trust in the reported fingerprint', () {
    expect(accept(QuickSaveMode.paired, encrypted: false), isFalse);
    expect(accept(QuickSaveMode.paired, encrypted: false, trust: true), isTrue);
    expect(
      shouldAutoAcceptDevice(
        mode: QuickSaveMode.paired,
        encrypted: false,
        certFingerprint: null,
        reportedFingerprint: 'other',
        trustUnencryptedFavorites: true,
        favorites: ['favorite'],
      ),
      isFalse,
    );
  });
}
