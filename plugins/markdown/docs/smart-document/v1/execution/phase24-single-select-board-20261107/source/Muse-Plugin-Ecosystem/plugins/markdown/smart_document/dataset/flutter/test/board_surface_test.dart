import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'original board cards move, undo and edit the same record at $width',
      (t) async {
        t.view.physicalSize = Size(width, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final fatal = WidgetController.hitTestWarningShouldBeFatal;
        WidgetController.hitTestWarningShouldBeFatal = true;
        addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = fatal);
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: MemoryStore(),
          objectId: '9e54912e-5dd8-4231-9b51-a2c5ca0b1f61',
          syncInterval: null,
        );
        await c.createField(
          '状态',
          'singleSelect',
          options: const [
            DatasetOptionDraft(name: '待处理', color: 1),
            DatasetOptionDraft(name: '进行中', color: 2),
          ],
        );
        final field = c.views.single.columns.last,
            todo = field.options.first.id,
            doing = field.options.last.id;
        final row = await c.addRow(
          cells: {
            'title': '同一条原记录',
            field.id: [todo],
          },
        );
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(controller: c, title: '项目数据库'),
            ),
          ),
        );
        await t.pumpAndSettle();
        Future<void> tap(Finder f) async {
          await t.ensureVisible(f);
          await t.pumpAndSettle();
          await t.tap(f);
          await t.pumpAndSettle();
        }

        await tap(find.byKey(const ValueKey('dataset.add-view')));
        await t.enterText(
          find.byKey(const ValueKey('dataset.view-name')),
          '任务看板',
        );
        await tap(find.byKey(const ValueKey('dataset.view-layout')));
        await tap(find.text('看板').last);
        expect(find.text('按单选字段分组'), findsOneWidget);
        await tap(find.byKey(const ValueKey('dataset.view-apply')));
        final board = c.views.singleWhere((v) => v.layout == 1);
        expect(board.board!.ready, true);
        expect(board.rows.single.id, row);
        final move = find.byKey(ValueKey('dataset.card-move.$row'));
        await tap(move);
        await tap(find.byKey(ValueKey('dataset.move-group.$doing')));
        expect(c.readRow(board.id, row).cells[field.id]!.selectedOptionIds, [
          doing,
        ]);
        await tap(find.byKey(const ValueKey('dataset.undo')));
        expect(c.readRow(board.id, row).cells[field.id]!.selectedOptionIds, [
          todo,
        ]);
        await tap(find.byKey(ValueKey('dataset.card.$row')));
        await tap(find.byKey(const ValueKey('dataset.record-field.title')));
        await t.enterText(
          find.byKey(const ValueKey('dataset.cell-input')),
          '卡片中编辑标题',
        );
        await tap(find.byKey(const ValueKey('dataset.cell-apply')));
        await tap(find.text('完成').last);
        expect(c.views.first.rows.single.cells['title']!.value, '卡片中编辑标题');
        await tap(find.byKey(ValueKey('dataset.group-add.$doing')));
        expect(
          find.byKey(const ValueKey('dataset.record-dialog')),
          findsOneWidget,
        );
        await tap(find.text('完成').last);
        expect(c.views.first.rows.length, 2);
        expect(
          c.views
              .singleWhere((v) => v.layout == 1)
              .board!
              .groups
              .singleWhere((g) => g.id == doing)
              .rowIds
              .length,
          1,
        );
        final epoch = c.localMutationEpoch;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(
                controller: c,
                title: '只读看板',
                viewId: board.id,
                allowEditing: false,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final card = find.byKey(ValueKey('dataset.card.$row'));
        await tap(card);
        final record = t.widget<ListTile>(
          find.byKey(const ValueKey('dataset.record-field.title')),
        );
        expect(record.enabled, false);
        expect(c.localMutationEpoch, epoch);
        await tap(find.text('完成').last);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox.shrink());
        await c.close();
      },
    );
  }
  testWidgets(
    'long-press drag updates the original grouping cell without copying a card',
    (t) async {
      t.view.physicalSize = const Size(1100, 800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: '92b02603-2c80-4e49-b43a-9e6c9d3909d9',
        syncInterval: null,
      );
      await c.createField(
        '状态',
        'singleSelect',
        options: const [
          DatasetOptionDraft(name: '待处理'),
          DatasetOptionDraft(name: '进行中'),
        ],
      );
      final f = c.views.single.columns.last,
          todo = f.options[0].id,
          doing = f.options[1].id;
      final row = await c.addRow(
            cells: {
              'title': '拖动原卡片',
              f.id: [todo],
            },
          ),
          id = await c.createBoardView('看板', f);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatasetSurface(controller: c, title: '看板', viewId: id),
          ),
        ),
      );
      await t.pumpAndSettle();
      final gesture = await t.startGesture(
        t.getCenter(find.byKey(ValueKey('dataset.card.$row'))),
      );
      await t.pump(const Duration(milliseconds: 650));
      await gesture.moveTo(
        t.getCenter(find.byKey(ValueKey('dataset.group.$doing'))),
      );
      await t.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await t.pumpAndSettle();
      expect(c.readRow(id, row).cells[f.id]!.selectedOptionIds, [doing]);
      expect(c.views.every((v) => v.rows.single.id == row), true);
      expect((c.bundle['objects'] as List).length, 2);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await c.close();
    },
  );
}
