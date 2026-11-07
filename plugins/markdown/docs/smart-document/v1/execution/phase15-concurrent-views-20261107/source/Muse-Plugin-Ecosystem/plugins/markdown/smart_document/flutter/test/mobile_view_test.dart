import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _MemoryStore implements DocumentStore {
  Map<String, dynamic>? snapshot;
  @override
  Future<Map<String, dynamic>?> read() async => snapshot;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    snapshot = value;
  }
}

Widget _app(SmartDocumentController c) => MaterialApp(
  localizationsDelegates: [AppFlowyEditorLocalizations.delegate],
  supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
  home: Scaffold(
    body: SmartDocumentView(controller: c, title: '移动文档'),
  ),
);
void main() {
  testWidgets(
    '320-430 mobile widths keep 44px targets and one inset-aware toolbar',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      tester.view.physicalSize = const Size(390, 844);
      final c = (await tester.runAsync(
        () => SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _MemoryStore(),
          objectId: '041c01d0-831a-408a-b8fa-190d40dd9e74',
        ),
      ))!;
      await tester.pumpWidget(_app(c));
      await tester.pump();
      await tester.tap(find.text('编辑'));
      await tester.pump(const Duration(milliseconds: 100));
      for (final width in [320.0, 360.0, 390.0, 430.0]) {
        tester.view.physicalSize = Size(width, 844);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await tester.pump();
        final keyboard = find.byKey(
          const ValueKey('smart-document.mobile.keyboard'),
        );
        final tools = find.byKey(const ValueKey('smart-document.mobile.tools'));
        expect(tools, findsOneWidget);
        expect(find.byTooltip('收起键盘'), findsOneWidget);
        expect(tester.getSize(keyboard).width, greaterThanOrEqualTo(44));
        expect(tester.getRect(keyboard).right, lessThanOrEqualTo(width));
        expect(tester.getRect(tools).bottom, lessThanOrEqualTo(544));
        await tester.tap(
          find.byKey(const ValueKey('smart-document.mobile.list')).first,
        );
        await tester.pump();
        expect(find.byTooltip('有序列表'), findsOneWidget);
        expect(find.byTooltip('无序列表'), findsOneWidget);
        expect(find.byTooltip('待办'), findsOneWidget);
        expect(
          tester.takeException(),
          isNull,
          reason: 'No layout error at $width',
        );
        await tester.tap(
          find.byKey(const ValueKey('smart-document.mobile.list')).last,
        );
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding();
        tester.testTextInput.hide();
        await tester.pump();
        await tester.tap(keyboard);
        await tester.pump();
        expect(
          tester.testTextInput.isVisible,
          isTrue,
          reason: 'Reopen IME even when client text is unchanged',
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(c.close);
    },
  );
  testWidgets(
    'nested heading and code content remain visible in the shared editor',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final c = (await tester.runAsync(
        () => SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _MemoryStore(),
          objectId: '041c01d0-831a-408a-b8fa-190d40dd9e85',
        ),
      ))!;
      await c.editor.apply(
        c.editor.transaction..insertText(c.blocks.first, 0, '父标题'),
      );
      await c.editor.apply(
        c.editor.transaction..insertNode(
          [0, 0],
          paragraphNode(text: 'print("子内容")'),
          deepCopy: false,
        ),
      );
      c.editor.selection = Selection.collapsed(Position(path: [0]));
      await tester.runAsync(() => c.convertSelection('heading', level: 2));
      c.editor.selection = Selection.collapsed(Position(path: [0, 0]));
      await tester.runAsync(() => c.convertSelection('code'));
      await tester.pumpWidget(_app(c));
      await tester.pump();
      expect(find.byType(AppFlowyRichText), findsNWidgets(2));
      final rendered = tester
          .widgetList<AppFlowyRichText>(find.byType(AppFlowyRichText))
          .map((w) => w.node.delta!.toPlainText())
          .join(' ');
      expect(rendered, contains('父标题'));
      expect(rendered, contains('print("子内容")'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(c.close);
    },
  );
  testWidgets('readonly mobile cannot enter writing or expose mutation tools', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final c = (await tester.runAsync(
      () => SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _MemoryStore(),
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e75',
        editable: false,
      ),
    ))!;
    await tester.pumpWidget(_app(c));
    await tester.pump();
    await tester.tap(find.text('编辑'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('smart-document.mobile.tools')),
      findsNothing,
    );
    expect(c.editor.editable, isFalse);
    await expectLater(
      c.insertParagraph('forbidden'),
      throwsA(isA<SmartDocumentFailure>()),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(c.close);
  });
}
