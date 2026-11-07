import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/conversation/conversation_models.dart';
import 'package:localsend_app/widget/conversation/conversation_entry_tile.dart';
import 'package:localsend_isolates/model/file_type.dart';

void main() {
  ConversationEntry entry(ConversationFileSummary file, {ConversationDirection direction = ConversationDirection.receive}) => ConversationEntry(
    entryId: ConversationEntry.buildEntryId(direction, 'test'),
    peerKey: 'peer',
    direction: direction,
    localSessionId: 'test',
    kind: ConversationEntryKind.file,
    outcome: ConversationOutcome.finished,
    createdAt: DateTime.utc(2026),
    finishedAt: DateTime.utc(2026),
    files: [file],
    text: null,
    error: null,
  );

  testWidgets('gallery result remains visible without a path', (tester) async {
    const file = ConversationFileSummary(
      fileId: '1',
      fileName: 'image.png',
      fileType: FileType.image,
      size: 10,
      outcome: ConversationFileOutcome.success,
      path: null,
      savedToGallery: true,
      error: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ConversationEntryTile(entry: entry(file))),
      ),
    );
    expect(find.text(t.progressPage.savedToGallery), findsOneWidget);
    expect(find.text('image.png'), findsOneWidget);
  });

  testWidgets('Android preview uses the full viewport behind its floating back button', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    const file = ConversationFileSummary(
      fileId: '1',
      fileName: 'missing.png',
      fileType: FileType.image,
      size: 10,
      outcome: ConversationFileOutcome.success,
      path: '/missing-c3-image.png',
      savedToGallery: false,
      error: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Scaffold(body: ConversationEntryTile(entry: entry(file))),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.broken_image_outlined));
    await tester.pumpAndSettle();
    final back = find.byType(BackButton);
    final viewer = find.byType(InteractiveViewer);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, Colors.black);
    expect(tester.getSize(viewer), const Size(360, 800));
    expect(tester.getRect(viewer).contains(tester.getCenter(back)), isTrue);
    expect(tester.getRect(back).left, 0);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(viewer, findsNothing);
    expect(find.byType(ConversationEntryTile), findsOneWidget);
  });

  for (final direction in ConversationDirection.values) {
    testWidgets('desktop previews a readable ${direction.name} image and Escape returns to the conversation', (tester) async {
      const file = ConversationFileSummary(
        fileId: '1',
        fileName: 'logo-256.png',
        fileType: FileType.image,
        size: 10,
        outcome: ConversationFileOutcome.success,
        path: 'assets/img/logo-256.png',
        savedToGallery: false,
        error: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: ConversationEntryTile(entry: entry(file, direction: direction)),
          ),
        ),
      );
      await tester.tap(find.byType(Image));
      await tester.pumpAndSettle();
      final viewer = find.byType(InteractiveViewer);
      final image = find.descendant(of: viewer, matching: find.byType(Image));
      final pixels = find.descendant(of: image, matching: find.byType(RawImage));
      for (var attempt = 0; attempt < 20 && tester.widget<RawImage>(pixels).image == null; attempt++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      expect(tester.widget<RawImage>(pixels).image, isNotNull);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(viewer, findsNothing);
    });
  }
}
