import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'original date field UI, civil range, clear undo, stale timezone draft at $width',
      (t) async {
        t.view.physicalSize = Size(width, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final store = MemoryStore();
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: store,
          objectId: '20841e64-27cf-4e0c-b7b5-3d6e3041a305',
          syncInterval: null,
        );
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(controller: c, title: '协作日期'),
            ),
          ),
        );
        await t.tap(find.byKey(const ValueKey('dataset.add-field')));
        await t.pumpAndSettle();
        await t.tap(find.text('日期').last);
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.field-name')),
          '交付日期',
        );
        await t.enterText(
          find.byKey(const ValueKey('dataset.field-timezone')),
          'Asia/Shanghai',
        );
        await t.tap(find.byKey(const ValueKey('dataset.field-apply')));
        await t.pumpAndSettle();
        final fieldId = c.views.single.columns.last.id;
        expect(c.views.single.columns.last.storageType, 2);
        expect(c.views.single.columns.last.timezone, 'Asia/Shanghai');
        await t.tap(find.byKey(const ValueKey('dataset.add-row')));
        await t.pumpAndSettle();
        final rowId = c.views.single.rows.single.id;
        Finder cell() => find.byKey(ValueKey('dataset.cell.$rowId.$fieldId'));
        await t.ensureVisible(cell());
        await t.pumpAndSettle();
        await t.tap(cell());
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.date-start')),
          '2026-11-06',
        );
        await t.tap(find.byKey(const ValueKey('dataset.date-range')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.date-end')),
          '2026-11-07',
        );
        await t.tap(find.byKey(const ValueKey('dataset.date-apply')));
        await t.pumpAndSettle();
        Map value() => c.views.single.rows.single.cells[fieldId]!.value as Map;
        expect(value()['start'], '2026-11-06');
        expect(value()['end'], '2026-11-07');
        expect(value()['includeTime'], false);
        expect(find.text('2026-11-06 → 2026-11-07'), findsOneWidget);
        await t.tap(cell());
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.date-start')),
          '2026-02-30',
        );
        final before = jsonEncode(c.snapshot['bundle']);
        await t.tap(find.byKey(const ValueKey('dataset.date-apply')));
        await t.pumpAndSettle();
        expect(find.textContaining('日期无效'), findsOneWidget);
        expect(jsonEncode(c.snapshot['bundle']), before);
        expect(
          (t.widget<TextField>(
            find.byKey(const ValueKey('dataset.date-start')),
          )).controller!.text,
          '2026-02-30',
        );
        await t.enterText(
          find.byKey(const ValueKey('dataset.date-start')),
          '2026-11-06',
        );
        // A remote field/schema edit must not reinterpret an old open draft.
        await c.configureDateField(
          c.views.single.columns.last,
          '交付日期',
          'America/New_York',
        );
        await t.tap(find.byKey(const ValueKey('dataset.date-apply')));
        await t.pumpAndSettle();
        expect(find.textContaining('字段或时区已变化'), findsOneWidget);
        expect(
          (t.widget<TextField>(
            find.byKey(const ValueKey('dataset.date-start')),
          )).controller!.text,
          '2026-11-06',
        );
        await t.tap(find.text('取消').last);
        await t.pumpAndSettle();
        await t.tap(cell());
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('dataset.date-clear')));
        await t.pumpAndSettle();
        expect(value()['start'], isNull);
        final undo = find.byKey(const ValueKey('dataset.undo'));
        await t.ensureVisible(undo);
        await t.tap(undo);
        await t.pumpAndSettle();
        expect(value()['start'], isNotNull);
        expect(c.views.single.columns.last.timezone, 'America/New_York');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await c.close();
        final reopened = await DatasetController.open(
          core: NativeDatasetCore(),
          store: store,
          objectId: '20841e64-27cf-4e0c-b7b5-3d6e3041a305',
          syncInterval: null,
        );
        expect(reopened.views.single.columns.last.timezone, 'America/New_York');
        expect(
          reopened.views.single.rows.single.cells[fieldId]!.value,
          value(),
        );
        await reopened.close();
      },
    );
  }
}
