import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'number settings preserve row precision and reject stale metadata at $width',
      (t) async {
        t.view.physicalSize = Size(width, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: MemoryStore(),
          objectId: '621b9e4e-b186-4832-99e0-65869d3a758f',
          syncInterval: null,
        );
        await c.createField('金额', 'number');
        final id = c.views.single.columns.last.id;
        const raw = '12345678901234567890.12345678';
        await c.addRow(cells: {id: raw});
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(controller: c, title: '显示格式'),
            ),
          ),
        );
        await t.pumpAndSettle();
        Future<void> open() async {
          final header = find.byKey(ValueKey('dataset.field.$id'));
          await t.ensureVisible(header);
          await t.pumpAndSettle();
          await t.tap(header);
          await t.pumpAndSettle();
        }

        await open();
        expect(find.text('数字字段设置'), findsOneWidget);
        await t.enterText(
          find.byKey(const ValueKey('dataset.field-name')),
          '预算',
        );
        await t.tap(find.byKey(const ValueKey('dataset.number-format')));
        await t.pumpAndSettle();
        await t.tap(find.text('欧元').last);
        await t.pumpAndSettle();
        final apply = find.byKey(const ValueKey('dataset.field-apply'));
        expect(t.getSize(apply).height, greaterThanOrEqualTo(44));
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(c.views.single.columns.last.name, '预算');
        expect(c.views.single.columns.last.numberFormat, 4);
        expect(c.views.single.rows.single.cells[id]!.numberInput, raw);
        expect(
          c.views.single.rows.single.cells[id]!.value,
          '€12.345.678.901.234.567.890,12',
        );
        final before = jsonEncode(c.bundle), epoch = c.localMutationEpoch;
        await open();
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(c.localMutationEpoch, epoch);
        expect(jsonEncode(c.bundle), before);
        await open();
        await t.enterText(
          find.byKey(const ValueKey('dataset.field-name')),
          '旧预算',
        );
        await c.configureNumberField(
          c.views.single.columns.last,
          5,
          name: '远端预算',
        );
        await t.pumpAndSettle();
        final remote = jsonEncode(c.bundle);
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(find.text('字段已变化或名称无效，请重新检查'), findsOneWidget);
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('dataset.field-name')),
              )
              .controller!
              .text,
          '旧预算',
        );
        expect(jsonEncode(c.bundle), remote);
        await t.tap(find.text('取消').last);
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox.shrink());
        await c.close();
      },
    );
  }
}
