import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/pages/receive_page.dart';
import 'package:localsend_app/provider/network/server/controller/receive_controller.dart';
import 'package:localsend_isolates/model/session_status.dart';

void main() {
  test('only legacy waiting requests dismiss receive options', () {
    expect(shouldDismissReceiveOptions(SessionStatus.waiting, TransferPresentation.conversation), isFalse);
    expect(shouldDismissReceiveOptions(SessionStatus.sending, TransferPresentation.legacy), isFalse);
    expect(shouldDismissReceiveOptions(SessionStatus.waiting, TransferPresentation.legacy), isTrue);
  });

  testWidgets('missing receive page leaves the root route intact', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('home')),
      ),
    );
    dismissReceiveOptions(navigator.currentState!);
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('legacy receive options return to the receive route', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('home')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: '$ReceivePage'),
          builder: (_) => const Text('receive'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Text('options'))));
    await tester.pumpAndSettle();
    dismissReceiveOptions(navigator.currentState!);
    await tester.pumpAndSettle();
    expect(find.text('receive'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
