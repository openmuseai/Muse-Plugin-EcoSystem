import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final modifier in [
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.controlLeft,
  ]) {
    testWidgets(
      'child shortcuts own history and readonly keys never bubble to parent: $modifier',
      (t) async {
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: MemoryStore(),
          objectId: '886ec6ed-e724-42f5-bc7e-42797f5c746c',
          syncInterval: null,
        );
        var parentUndo = 0, editable = true;
        Widget app() => MaterialApp(
          home: Scaffold(
            body: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  meta: true,
                ): () =>
                    parentUndo++,
                const SingleActivator(
                  LogicalKeyboardKey.keyZ,
                  control: true,
                ): () =>
                    parentUndo++,
              },
              child: DatasetSurface(
                controller: c,
                title: '子表格',
                allowEditing: editable,
              ),
            ),
          ),
        );
        Future<void> key({bool redo = false}) async {
          await t.sendKeyDownEvent(modifier);
          if (redo) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await t.sendKeyEvent(LogicalKeyboardKey.keyZ);
          if (redo) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await t.sendKeyUpEvent(modifier);
          await t.pumpAndSettle();
        }

        await t.pumpWidget(app());
        await t.tap(find.byKey(const ValueKey('dataset.add-row')));
        await t.pumpAndSettle();
        final id = c.views.single.rows.single.id;
        await t.tap(find.byKey(ValueKey('dataset.cell.$id.title')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          '本机编辑',
        );
        await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
        await t.pumpAndSettle();
        await key();
        expect(c.views.single.rows.single.cells['title']!.value, isNull);
        await key(redo: true);
        expect(c.views.single.rows.single.cells['title']!.value, '本机编辑');
        expect(parentUndo, 0);
        editable = false;
        await t.pumpWidget(app());
        await t.pumpAndSettle();
        await t.tap(find.text('子表格'));
        await key();
        expect(c.views.single.rows.single.cells['title']!.value, '本机编辑');
        expect(parentUndo, 0);
        await t.pumpWidget(const SizedBox());
        await c.close();
      },
    );
  }
}
