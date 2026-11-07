import 'dart:ui' show CheckedState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'original single/multi select UI, clear and schema preconditions at $width',
      (t) async {
        final semantics = t.ensureSemantics();
        try {
          t.view.physicalSize = Size(width, 850);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final c = await DatasetController.open(
            core: NativeDatasetCore(),
            store: MemoryStore(),
            objectId: '9ac3ad58-105c-4cb8-80da-5912b95f34a6',
            syncInterval: null,
          );
          await t.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: DatasetSurface(controller: c, title: '选择字段'),
              ),
            ),
          );
          Future<void> create(String type, String name) async {
            await t.tap(find.byKey(const ValueKey('dataset.add-field')));
            await t.pumpAndSettle();
            await t.tap(find.text(type).last);
            await t.pumpAndSettle();
            await t.enterText(
              find.byKey(const ValueKey('dataset.field-name')),
              name,
            );
            await t.enterText(
              find.byKey(const ValueKey('dataset.field-options')),
              '待办,A😀\n进行中\n已完成',
            );
            await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
            await t.pumpAndSettle();
          }

          await create('单选', '状态');
          await create('多选', '标签');
          expect(c.views.single.columns.where((f) => f.isChoice), hasLength(2));
          await t.tap(find.byKey(const ValueKey('dataset.add-row')));
          await t.pumpAndSettle();
          final row = c.views.single.rows.single;
          DatasetColumn col(String name) =>
              c.views.single.columns.firstWhere((f) => f.name == name);
          Future<void> open(DatasetColumn field) async {
            final target = find.byKey(
              ValueKey('dataset.cell.${row.id}.${field.id}'),
            );
            await t.ensureVisible(target);
            await t.pumpAndSettle();
            await t.tap(target);
            await t.pumpAndSettle();
          }

          final state = col('状态'), tags = col('标签');
          await open(state);
          final first = find.byKey(
            ValueKey('dataset.choice-option.${state.options.first.id}'),
          );
          expect(t.getSize(first).height, greaterThanOrEqualTo(44));
          expect(
            t.getSemantics(first).flagsCollection.isChecked,
            CheckedState.isFalse,
          );
          await t.tap(first);
          await t.pump();
          expect(
            t.getSemantics(first).flagsCollection.isChecked,
            CheckedState.isTrue,
          );
          await t.tap(find.byKey(const ValueKey('dataset.choice-apply')));
          await t.pumpAndSettle();
          expect(c.views.single.rows.single.cells[state.id]!.value, '待办,A😀');
          expect(
            c.views.single.rows.single.cells[state.id]!.selectedOptionIds,
            [state.options.first.id],
          );
          await open(tags);
          await t.tap(
            find.byKey(ValueKey('dataset.choice-option.${tags.options[1].id}')),
          );
          await t.tap(
            find.byKey(ValueKey('dataset.choice-option.${tags.options[0].id}')),
          );
          await t.tap(find.byKey(const ValueKey('dataset.choice-apply')));
          await t.pumpAndSettle();
          expect(c.views.single.rows.single.cells[tags.id]!.value, [
            '进行中',
            '待办,A😀',
          ]);
          await open(state);
          await c.renameField(state, '新状态');
          await t.pump();
          await t.tap(
            find.byKey(
              ValueKey('dataset.choice-option.${state.options.last.id}'),
            ),
          );
          await t.tap(find.byKey(const ValueKey('dataset.choice-apply')));
          await t.pumpAndSettle();
          expect(find.text('内容或选项已变化，请取消后重新打开'), findsOneWidget);
          expect(c.views.single.rows.single.cells[state.id]!.value, '待办,A😀');
          await t.tap(find.text('取消'));
          await t.pumpAndSettle();
          await open(col('新状态'));
          await t.tap(find.byKey(const ValueKey('dataset.choice-clear')));
          await t.tap(find.byKey(const ValueKey('dataset.choice-apply')));
          await t.pumpAndSettle();
          expect(
            c.views.single.rows.single.cells[state.id]!.selectedOptionIds,
            isEmpty,
          );
          final reopened = await DatasetController.open(
            core: c.core,
            store: MemoryStore(),
            objectId: c.objectId,
            initialBundle: c.bundle,
            syncInterval: null,
          );
          expect(
            reopened.views.single.columns
                .firstWhere((f) => f.id == state.id)
                .options
                .first
                .name,
            '待办,A😀',
          );
          expect(
            reopened.views.single.rows.single.cells[tags.id]!.selectedOptionIds,
            tags.options.take(2).map((v) => v.id).toList().reversed.toList(),
          );
          await reopened.close();
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await c.close();
        } finally {
          semantics.dispose();
        }
      },
    );
  }
}
