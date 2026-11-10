import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/conversation_view_provider.dart';
import 'package:localsend_app/widget/conversation/conversation_list.dart';
import 'package:localsend_isolates/model/device.dart';

void main() {
  ConversationPeerView view(String name, {required bool favorite}) => ConversationPeerView(
    peerKey: name,
    alias: name,
    deviceType: DeviceType.desktop,
    online: false,
    isFavorite: favorite,
    device: null,
    lastEntry: null,
    entryCount: 0,
    hasActiveSend: false,
    hasActiveReceive: false,
  );

  testWidgets('groups devices and collapses each group independently', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationList(
            views: [view('Saved device', favorite: true), view('Nearby device', favorite: false)],
            selectedPeerKey: null,
            onTap: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Saved device'), findsOneWidget);
    expect(find.text('Nearby device'), findsOneWidget);
    expect(find.text('0 / 1'), findsNWidgets(2));
    expect(find.text(t.general.offline), findsNWidgets(2));
    await tester.tap(find.text(t.conversation.myFavorites));
    await tester.pumpAndSettle();
    expect(find.text('Saved device'), findsNothing);
    expect(find.text('Nearby device'), findsOneWidget);
    await tester.tap(find.text(t.sendTab.nearbyDevices));
    await tester.pumpAndSettle();
    expect(find.text('Nearby device'), findsNothing);
  });
}
