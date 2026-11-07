import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'date rules calendar, original prefill and hidden record editing at $width',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: MemoryStore(),
          objectId: '03f4498a-4eee-4a23-9e67-e70bb48f9fae',
          syncInterval: null,
        );
        await c.createField('交付日期', 'date', timezone: 'Asia/Shanghai');
        final field = c.views.single.columns.last;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(controller: c, title: '日期筛选'),
            ),
          ),
        );
        Future<void> tap(Finder f) async {
          await t.ensureVisible(f);
          await t.pumpAndSettle();
          await t.tap(f);
          await t.pumpAndSettle();
        }

        await tap(find.byKey(const ValueKey('dataset.filters')));
        await tap(find.byKey(const ValueKey('dataset.rules-add-filter')));
        await tap(find.byType(DropdownButtonFormField<String>).first);
        await tap(find.text('交付日期').last);
        expect(find.textContaining('Asia/Shanghai'), findsOneWidget);
        await t.enterText(find.byType(TextFormField), '2026-11-07');
        await tap(find.byTooltip('选择筛选日期'));
        expect(find.byType(DatePickerDialog), findsOneWidget);
        final cancel = MaterialLocalizations.of(
          t.element(find.byType(DatePickerDialog)),
        ).cancelButtonLabel;
        await tap(find.text(cancel).last);
        await tap(find.byKey(const ValueKey('dataset.rules-apply')));
        expect(c.views.single.rulesReady, true);
        await tap(find.byKey(const ValueKey('dataset.add-row')));
        expect(c.views.single.rows, hasLength(1));
        expect(
          (c.views.single.rows.single.cells[field.id]!.value as Map)['start'],
          '2026-11-07',
        );
        await tap(find.byKey(const ValueKey('dataset.filters')));
        await tap(find.byType(DropdownButtonFormField<int>).first);
        await tap(find.text('开始日期不为空').last);
        await tap(find.byKey(const ValueKey('dataset.rules-apply')));
        await tap(find.byKey(const ValueKey('dataset.add-row')));
        expect(c.views.single.rows, hasLength(1));
        expect(c.views.single.allRows, hasLength(2));
        expect(find.text('记录已创建，当前筛选下不可见'), findsOneWidget);
        await tap(find.text('编辑新记录').last);
        expect(
          find.byKey(const ValueKey('dataset.record-dialog')),
          findsOneWidget,
        );
        await tap(find.byKey(ValueKey('dataset.record-field.${field.id}')));
        await t.enterText(
          find.byKey(const ValueKey('dataset.date-start')),
          '2026-11-08',
        );
        await tap(find.byKey(const ValueKey('dataset.date-apply')));
        expect(c.views.single.rows, hasLength(2));
        await tap(find.text('完成').last);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await c.close();
      },
    );
  }
}
