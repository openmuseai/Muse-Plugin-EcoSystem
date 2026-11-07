import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'exact number draft, no-change apply, invalid atomic input and stale field at $width',
      (t) async {
        t.view.physicalSize = Size(width, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: MemoryStore(),
          objectId: '886ec6ed-e724-42f5-bc7e-42797f5c7420',
          syncInterval: null,
        );
        await c.createField('金额', 'number');
        await c.configureNumberField(c.views.single.columns.last, 1);
        final fieldId = c.views.single.columns.last.id;
        final rowId = await c.addRow(
          cells: {fieldId: '9007199254740993.123456789'},
        );
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(controller: c, title: '数字协作'),
            ),
          ),
        );
        await t.pumpAndSettle();
        Finder cell() => find.byKey(ValueKey('dataset.cell.$rowId.$fieldId'));
        Future<void> open() async {
          await t.ensureVisible(cell());
          await t.pumpAndSettle();
          await t.tap(cell());
          await t.pumpAndSettle();
        }

        final before = jsonEncode(c.bundle),
            epoch = c.localMutationEpoch,
            undo = c.canUndo;
        await open();
        final input = find.byKey(const ValueKey('dataset.cell-input'));
        final apply = find.byKey(const ValueKey('dataset.cell-apply'));
        expect(
          t.widget<TextField>(input).controller!.text,
          '9007199254740993.123456789',
        );
        expect(
          c.views.single.rows.single.cells[fieldId]!.value,
          isNot('9007199254740993.123456789'),
        );
        expect(t.getSize(apply).height, greaterThanOrEqualTo(44));
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(jsonEncode(c.bundle), before);
        expect(c.localMutationEpoch, epoch);
        expect(c.canUndo, undo);
        await open();
        await t.enterText(input, '123abc');
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(find.text('请输入有效数字，支持小数和科学计数法'), findsOneWidget);
        expect(t.widget<TextField>(input).controller!.text, '123abc');
        expect(t.widget<TextField>(input).focusNode!.hasFocus, isTrue);
        expect(jsonEncode(c.bundle), before);
        await t.enterText(input, '-1.25e-2');
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(
          c.views.single.rows.single.cells[fieldId]!.numberInput,
          '-0.0125',
        );
        await open();
        await t.enterText(input, '999.125');
        await c.configureNumberField(c.views.single.columns.last, 4);
        await t.pumpAndSettle();
        final schemaChanged = jsonEncode(c.bundle);
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(find.text('字段设置已被修改，请取消后重新编辑'), findsOneWidget);
        expect(t.widget<TextField>(input).controller!.text, '999.125');
        expect(jsonEncode(c.bundle), schemaChanged);
        await t.tap(find.text('取消').last);
        await t.pumpAndSettle();
        await open();
        await t.enterText(input, '0');
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(c.views.single.rows.single.cells[fieldId]!.numberInput, '0');
        await open();
        await t.enterText(input, '');
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(c.views.single.rows.single.cells[fieldId]!.numberInput, '');
        await c.history();
        await t.pumpAndSettle();
        expect(c.views.single.rows.single.cells[fieldId]!.numberInput, '0');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump();
        await c.close();
      },
    );
  }
}
