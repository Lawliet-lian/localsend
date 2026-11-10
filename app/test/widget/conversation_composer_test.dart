import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/util/native/file_picker.dart';
import 'package:localsend_app/widget/conversation/conversation_composer.dart';
import 'package:localsend_isolates/model/file_type.dart';

/// P6c：输入栏的行为合同测试（门槛：双击只发一次；文字保持原样；离线禁止发送）。
void main() {
  Future<void> pumpComposer(
    WidgetTester tester, {
    required bool enabled,
    String initialValue = '',
    required ValueChanged<String> onSend,
    ValueChanged<String>? onChanged,
    VoidCallback? onPickAttachment,
    bool attachmentEnabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationComposer(
            initialValue: initialValue,
            enabled: enabled,
            onChanged: onChanged ?? (_) {},
            onSend: onSend,
            onPickAttachment: onPickAttachment,
            attachmentEnabled: attachmentEnabled,
          ),
        ),
      ),
    );
  }

  group('ConversationComposer', () {
    testWidgets('file draft can be removed or submitted with text', (tester) async {
      const file = CrossFile(
        name: 'video.mp4',
        fileType: FileType.video,
        size: 3,
        thumbnail: null,
        asset: null,
        path: null,
        bytes: [1, 2, 3],
        lastModified: null,
        lastAccessed: null,
      );
      int? removed;
      List<CrossFile>? sent;
      String? text;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationComposer(
              initialValue: 'hello',
              enabled: true,
              onChanged: (_) {},
              onSend: (_) {},
              fileDrafts: const [file],
              onRemoveFile: (index) => removed = index,
              onSendFiles: (value, image, files) {
                text = value;
                sent = files;
              },
            ),
          ),
        ),
      );
      expect(find.textContaining('video.mp4'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      expect(removed, 0);
      await tester.tap(find.byIcon(Icons.send));
      expect(text, 'hello');
      expect(sent, [file]);
    });
    testWidgets('image draft and text are submitted together to the image handler', (tester) async {
      final bytes = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aWQAAAAASUVORK5CYII=');
      String? sentText;
      Uint8List? sentImage;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationComposer(
              initialValue: 'hello',
              enabled: true,
              onChanged: (_) {},
              onSend: (_) => fail('text must be queued with the image'),
              imageDraft: bytes,
              onImageDraftChanged: (_) {},
              onSendImage: (text, image) {
                sentText = text;
                sentImage = image;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.send));
      expect(sentText, 'hello');
      expect(sentImage, same(bytes));
    });
    testWidgets('desktop attachment buttons choose the requested type', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      FilePickerOption? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConversationComposer(
              initialValue: '',
              enabled: true,
              onChanged: (_) {},
              onSend: (_) {},
              onPickAttachmentOption: (option) => selected = option,
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.folder));
      expect(selected, FilePickerOption.folder);
      await tester.tap(find.byIcon(Icons.description));
      expect(selected, FilePickerOption.file);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('offline draft is editable while send remains disabled', (tester) async {
      final changes = <String>[];
      await pumpComposer(tester, enabled: false, onSend: (_) {}, onChanged: changes.add);
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();
      expect(changes.last, 'draft');
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send)).onPressed, isNull);
    });

    testWidgets('Enter sends; Shift+Enter and Command+Enter insert a newline', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final sent = <String>[];
      final changes = <String>[];
      await pumpComposer(tester, enabled: true, onSend: sent.add, onChanged: changes.add);
      await tester.enterText(find.byType(TextField), 'first');
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(changes.last, 'first\n\n');
      expect(sent, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, ['first\n\n']);
      expect(changes.last, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('Enter during IME composition does not send', (tester) async {
      final sent = <String>[];
      await pumpComposer(tester, enabled: true, onSend: sent.add);
      await tester.showKeyboard(find.byType(TextField));
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'pin',
          selection: TextSelection.collapsed(offset: 3),
          composing: TextRange(start: 0, end: 3),
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sent, isEmpty);
    });
    testWidgets('testShowsDraftInitialValue', (tester) async {
      await pumpComposer(tester, enabled: true, initialValue: 'draft text', onSend: (_) {});

      expect(find.text('draft text'), findsOneWidget);
    });

    testWidgets('testSendPassesTextVerbatimWithoutTrim', (tester) async {
      String? sent;
      await pumpComposer(tester, enabled: true, onSend: (text) => sent = text);

      await tester.enterText(find.byType(TextField), '  hello\nworld  ');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 原样传出：前导空格与换行都不允许丢失（方案 6.2）
      expect(sent, '  hello\nworld  ');
      // 提交后输入框清空
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    });

    testWidgets('testDoubleTapSendsOnlyOnce', (tester) async {
      final sent = <String>[];
      await pumpComposer(tester, enabled: true, onSend: sent.add);

      await tester.enterText(find.byType(TextField), 'once');
      await tester.pump();
      // 连续双击发送按钮：提交锁 + 输入框清空保证只发出第一条
      await tester.tap(find.byIcon(Icons.send));
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sent, ['once']);
    });

    testWidgets('testEmptyTextCannotSend', (tester) async {
      final sent = <String>[];
      await pumpComposer(tester, enabled: true, onSend: sent.add);

      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sent, isEmpty);
    });

    testWidgets('testOfflineCannotSend', (tester) async {
      final sent = <String>[];
      await pumpComposer(tester, enabled: false, onSend: sent.add);

      await tester.enterText(find.byType(TextField), 'queued while offline');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 离线设备禁止发送（门槛），但草稿同步不受影响
      expect(sent, isEmpty);
    });

    testWidgets('testOnChangedPropagatesEveryKeystroke', (tester) async {
      final changes = <String>[];
      await pumpComposer(tester, enabled: true, onSend: (_) {}, onChanged: changes.add);

      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();

      expect(changes.last, 'abc');
      // 提交时同步清空草稿（onChanged('')）
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();
      expect(changes.last, isEmpty);
    });

    testWidgets('testResendAllowedAfterNewInput', (tester) async {
      final sent = <String>[];
      await pumpComposer(tester, enabled: true, onSend: sent.add);

      await tester.enterText(find.byType(TextField), 'first');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 重新输入非空文本解除提交锁：允许第二条（新 session 新记录）
      await tester.enterText(find.byType(TextField), 'second');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sent, ['first', 'second']);
    });

    testWidgets('testHintTextVisible', (tester) async {
      await pumpComposer(tester, enabled: true, onSend: (_) {});

      expect(find.text(t.conversation.composeHint), findsOneWidget);
    });
  });

  // ---- P9b 附件按钮（dumb 合同：传与不传决定渲染，门槛只控制置灰） ----

  group('P9b 附件按钮', () {
    testWidgets('testAttachmentButtonAbsentWithoutCallback', (tester) async {
      // 未传 onPickAttachment（既有纯文字调用点）：按钮不出现
      await pumpComposer(tester, enabled: true, onSend: (_) {});

      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('testAttachmentButtonInvokesCallback', (tester) async {
      var picks = 0;
      await pumpComposer(tester, enabled: true, onSend: (_) {}, onPickAttachment: () => picks++);

      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pump();

      expect(picks, 1);
    });

    testWidgets('testAttachmentDisabledWhenGateClosed', (tester) async {
      var picks = 0;
      // 门槛不满足（selection 非空/活跃发送/picking）：按钮置灰，点击无效
      await pumpComposer(
        tester,
        enabled: true,
        onSend: (_) {},
        onPickAttachment: () => picks++,
        attachmentEnabled: false,
      );

      expect(tester.widget<IconButton>(find.byType(IconButton).first).onPressed, isNull);
      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pump();
      expect(picks, 0);
    });

    testWidgets('testAttachmentDisabledWhenOffline', (tester) async {
      var picks = 0;
      // 离线（enabled=false）：附件按钮同样置灰，与发送按钮一致
      await pumpComposer(tester, enabled: false, onSend: (_) {}, onPickAttachment: () => picks++);

      await tester.tap(find.byIcon(Icons.attach_file));
      await tester.pump();
      expect(picks, 0);
    });
  });
}
