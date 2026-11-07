import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _MemoryStore implements DocumentStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> value) async {}
}

Widget _app(SmartDocumentController c) => MaterialApp(
  localizationsDelegates: [AppFlowyEditorLocalizations.delegate],
  supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
  home: Scaffold(
    body: SmartDocumentView(controller: c, title: '文档'),
  ),
);

void main() {
  testWidgets(
    'mobile reading mode does not revoke permission after desktop resize',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final c = (await tester.runAsync(
        () => SmartDocumentController.open(
          core: NativeDocumentCore(),
          store: _MemoryStore(),
          objectId: '041c01d0-831a-408a-b8fa-190d40dd9e91',
        ),
      ))!;
      await tester.pumpWidget(_app(c));
      await tester.pump();
      expect(c.editor.editable, isFalse);
      expect(c.canWrite, isTrue);
      tester.view.physicalSize = const Size(1100, 900);
      await tester.pump();
      expect(c.editor.editable, isTrue);
      expect(find.text('只读'), findsNothing);
      await tester.runAsync(() => c.insertParagraph('可继续编辑'));
      expect(c.blocks.last.delta!.toPlainText(), '可继续编辑');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(c.close);
    },
  );
}
