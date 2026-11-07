import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'linked view UI keeps identity, local switching and stale name at $width',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: MemoryStore(),
          objectId: '7a8a6672-13d3-43dd-bc2b-49d43f71d839',
          syncInterval: null,
        );
        final first = c.views.single.id;
        await c.addRow(cells: {'title': '共享记录'});
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(
                controller: c,
                title: '多视图',
                embedded: true,
                viewId: first,
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('dataset.add-view')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.view-name')),
          '我的视图',
        );
        final apply = find.byKey(const ValueKey('dataset.view-apply'));
        expect(t.getSize(apply).height, greaterThanOrEqualTo(44));
        await t.tap(apply);
        await t.pumpAndSettle();
        final second = c.views.singleWhere((v) => v.name == '我的视图').id;
        final picker = find.byKey(const ValueKey('dataset.view-picker'));
        expect(t.widget<DropdownButton<String>>(picker).value, second);
        expect(c.views.first.id, first);
        expect(c.views[0].rows.single.id, c.views[1].rows.single.id);
        await t.tap(find.byKey(const ValueKey('dataset.undo')));
        await t.pumpAndSettle();
        expect(c.views.length, 1);
        expect(t.widget<DropdownButton<String>>(picker).value, isNull);
        expect(find.text('指定视图不可用，原引用保留'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('dataset.redo')));
        await t.pumpAndSettle();
        expect(t.widget<DropdownButton<String>>(picker).value, second);
        final epoch = c.localMutationEpoch;
        await t.tap(picker);
        await t.pumpAndSettle();
        await t.tap(find.text('表格').last);
        await t.pumpAndSettle();
        expect(t.widget<DropdownButton<String>>(picker).value, first);
        expect(c.localMutationEpoch, epoch);
        await t.tap(picker);
        await t.pumpAndSettle();
        await t.tap(find.text('我的视图').last);
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('dataset.view-settings')));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('dataset.view-name')),
          '旧名称',
        );
        await c.renameView(c.views.singleWhere((v) => v.id == second), '远端视图');
        await t.pumpAndSettle();
        await t.tap(apply);
        await t.pumpAndSettle();
        expect(find.text('视图已变化或名称无效，请重新检查'), findsOneWidget);
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('dataset.view-name')),
              )
              .controller!
              .text,
          '旧名称',
        );
        expect(c.views.singleWhere((v) => v.id == second).name, '远端视图');
        await t.tap(find.text('取消').last);
        await t.pumpAndSettle();
        expect(t.widget<DropdownButton<String>>(picker).value, second);
        await t.pumpWidget(const SizedBox.shrink());
        await c.close();
      },
    );
  }
}
