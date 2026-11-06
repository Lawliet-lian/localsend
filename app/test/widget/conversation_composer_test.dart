import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/widget/conversation/conversation_composer.dart';

/// P6c：输入栏的行为合同测试（门槛：双击只发一次；文字保持原样；离线禁止发送）。
void main() {
  Future<void> pumpComposer(
    WidgetTester tester, {
    required bool enabled,
    String initialValue = '',
    required ValueChanged<String> onSend,
    ValueChanged<String>? onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConversationComposer(
            initialValue: initialValue,
            enabled: enabled,
            onChanged: onChanged ?? (_) {},
            onSend: onSend,
          ),
        ),
      ),
    );
  }

  group('ConversationComposer', () {
    testWidgets('testShowsDraftInitialValue', (tester) async {
      await pumpComposer(tester, enabled: true, initialValue: 'draft text', onSend: (_) {});

      expect(find.text('draft text'), findsOneWidget);
    });

    testWidgets('testSendPassesTextVerbatimWithoutTrim', (tester) async {
      String? sent;
      await pumpComposer(tester, enabled: true, onSend: (text) => sent = text);

      await tester.enterText(find.byType(TextField), '  hello\nworld  ');
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
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 离线设备禁止发送（门槛），但草稿同步不受影响
      expect(sent, isEmpty);
    });

    testWidgets('testOnChangedPropagatesEveryKeystroke', (tester) async {
      final changes = <String>[];
      await pumpComposer(tester, enabled: true, onSend: (_) {}, onChanged: changes.add);

      await tester.enterText(find.byType(TextField), 'abc');

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
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      // 重新输入非空文本解除提交锁：允许第二条（新 session 新记录）
      await tester.enterText(find.byType(TextField), 'second');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pump();

      expect(sent, ['first', 'second']);
    });

    testWidgets('testHintTextVisible', (tester) async {
      await pumpComposer(tester, enabled: true, onSend: (_) {});

      expect(find.text(t.conversation.composeHint), findsOneWidget);
    });
  });
}
