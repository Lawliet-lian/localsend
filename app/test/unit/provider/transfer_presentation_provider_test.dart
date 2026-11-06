import 'package:flutter_test/flutter_test.dart';
import 'package:localsend_app/model/conversation/transfer_presentation.dart';
import 'package:localsend_app/provider/transfer_presentation_provider.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// P6a：展示模式存储的单元测试。
/// startSession 本身依赖 Rust/isolate 无法纯 Dart 集成测试（P0 已核实），
/// 因此本批验证机制组件：默认 legacy、每 session 独立、清理同步。
void main() {
  late RefenaContainer container;
  late TransferPresentationNotifier notifier;

  setUp(() {
    container = RefenaContainer();
    notifier = container.notifier(transferPresentationProvider);
  });

  tearDown(() {
    // RefenaContainer 实现 Ref.dispose(provider) 语义，整个容器销毁需用 disposeContainer()
    container.disposeContainer();
  });

  group('TransferPresentationNotifier', () {
    test('testGetDefaultLegacy', () {
      // 未记录的 session（包括所有 legacy 旧调用点）默认返回 legacy
      expect(notifier.get('unknown-session'), TransferPresentation.legacy);
      expect(container.read(transferPresentationProvider), isEmpty);
    });

    test('testSetConversationIsIndependentPerSession', () {
      notifier.set('session-a', TransferPresentation.conversation);

      // 每个 session 独立保存：a 是 conversation，b 不受影响仍是 legacy
      expect(notifier.get('session-a'), TransferPresentation.conversation);
      expect(notifier.get('session-b'), TransferPresentation.legacy);
    });

    test('testSetLegacyRemovesEntry', () {
      notifier.set('session-a', TransferPresentation.conversation);
      // 显式改回 legacy 时映射条目被移除（legacy 是默认值不占存储）
      notifier.set('session-a', TransferPresentation.legacy);

      expect(notifier.get('session-a'), TransferPresentation.legacy);
      expect(container.read(transferPresentationProvider), isEmpty);
    });

    test('testRemove', () {
      notifier.set('session-a', TransferPresentation.conversation);
      notifier.set('session-b', TransferPresentation.conversation);
      notifier.remove('session-a');

      // 移除只影响目标 session
      expect(notifier.get('session-a'), TransferPresentation.legacy);
      expect(notifier.get('session-b'), TransferPresentation.conversation);
    });

    test('testRemoveUnknownIsNoop', () {
      notifier.set('session-a', TransferPresentation.conversation);
      notifier.remove('not-exist');

      expect(notifier.get('session-a'), TransferPresentation.conversation);
    });

    test('testClearAll', () {
      notifier.set('session-a', TransferPresentation.conversation);
      notifier.set('session-b', TransferPresentation.conversation);
      notifier.clearAll();

      expect(container.read(transferPresentationProvider), isEmpty);
    });

    test('testStateIsImmutable', () {
      // set/remove 都产生新 Map，不原地修改旧 state（保证 watcher 收到变更）
      final before = container.read(transferPresentationProvider);
      notifier.set('session-a', TransferPresentation.conversation);
      final after = container.read(transferPresentationProvider);

      expect(identical(before, after), isFalse);
      expect(before, isEmpty);
      expect(after, {'session-a': TransferPresentation.conversation});
    });
  });
}
