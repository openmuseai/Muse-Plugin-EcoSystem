import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets('dataset editing, timeline and fields at width $width', (
      t,
    ) async {
      t.view.physicalSize = Size(width, 850);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: '13ca0639-11d1-4c15-9151-0a1886fdb580',
        syncInterval: null,
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatasetSurface(controller: c, title: '项目数据'),
          ),
        ),
      );
      final add = find.byKey(const ValueKey('dataset.add-row'));
      expect(t.getSize(add).height, greaterThanOrEqualTo(44));
      await t.tap(add);
      await t.pumpAndSettle();
      expect(c.views.single.rows, hasLength(1));
      final row = c.views.single.rows.single;
      await t.tap(find.byKey(ValueKey('dataset.cell.${row.id}.title')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('dataset.cell-input')),
        '多端协作😀',
      );
      await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
      await t.pumpAndSettle();
      expect(c.views.single.rows.single.cells['title']!.value, '多端协作😀');
      await t.tap(find.byKey(const ValueKey('dataset.undo')));
      await t.pumpAndSettle();
      expect(c.views.single.rows.single.cells['title']!.value, isNull);
      await t.tap(find.byKey(const ValueKey('dataset.undo')));
      await t.pumpAndSettle();
      expect(c.views.single.rows, isEmpty);
      await t.tap(find.byKey(const ValueKey('dataset.redo')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('dataset.redo')));
      await t.pumpAndSettle();
      expect(c.views.single.rows.single.cells['title']!.value, '多端协作😀');
      await t.tap(find.byKey(const ValueKey('dataset.field.title')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const ValueKey('dataset.field-name')),
        '任务名称',
      );
      await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
      await t.pumpAndSettle();
      expect(c.views.single.columns.first.name, '任务名称');
      expect(c.views.single.columns.first.id, 'title');
      expect(c.views.single.rows.single.cells['title']!.value, '多端协作😀');
      await t.tap(find.byKey(const ValueKey('dataset.add-field')));
      await t.pumpAndSettle();
      await t.tap(find.text('数字').last);
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const ValueKey('dataset.field-name')), '预算');
      await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
      await t.pumpAndSettle();
      expect(c.views.single.columns.last.semanticType, 'number');
      expect(c.views.single.columns.last.name, '预算');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await c.close();
    });
  }
  testWidgets('stale dialog preserves peer update and explicit draft', (
    t,
  ) async {
    final traced = TracedCore();
    final cloud = FakeCloud(traced);
    final c = await DatasetController.open(
      core: traced,
      store: MemoryStore(),
      providerFactory: cloud.provider,
      createRemote: true,
      objectId: '13ca0639-11d1-4c15-9151-0a1886fdb581',
      syncInterval: null,
    );
    await c.addRow(cells: {'title': '初始'});
    await c.synchronize();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DatasetSurface(controller: c, title: '协作数据'),
        ),
      ),
    );
    final row = c.views.single.rows.single,
        field = c.views.single.columns.first;
    await t.tap(find.byKey(ValueKey('dataset.cell.${row.id}.title')));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const ValueKey('dataset.cell-input')),
      '未提交草稿',
    );
    // Incoming transaction while the route holds a captured precondition.
    final peer = NativeDatasetCore();
    final state = peer.call({
      'action': 'open',
      'objectId': c.objectId,
      'bundle': c.bundle,
    });
    peer.call({
      'action': 'command',
      'handle': state['handle'],
      'command': {
        'op': 'setCell',
        'rowId': row.id,
        'fieldId': field.id,
        'expectedHash': row.cells[field.id]!.hash,
        'value': '对方已更新',
      },
    });
    final update = peer.call({
      'action': 'syncObject',
      'handle': state['handle'],
      'objectId': row.id,
    });
    cloud.states[row.id] = base64Decode(update['docState'] as String);
    peer.call({'action': 'close', 'handle': state['handle']});
    await c.synchronize();
    await t.tap(find.byKey(const ValueKey('dataset.cell-apply')));
    await t.pumpAndSettle();
    expect(find.text('内容已被修改，请取消后重新编辑'), findsOneWidget);
    expect(c.views.single.rows.single.cells[field.id]!.value, '对方已更新');
    expect(find.text('未提交草稿'), findsOneWidget);
    await t.tap(find.text('取消'));
    await t.pumpAndSettle();
    await t.pumpWidget(const SizedBox());
    await c.close();
  });
}
