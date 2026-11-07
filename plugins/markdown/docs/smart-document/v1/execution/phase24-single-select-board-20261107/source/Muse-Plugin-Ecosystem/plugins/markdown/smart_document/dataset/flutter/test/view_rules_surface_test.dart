import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  for (final width in [320.0, 430.0, 1100.0]) {
    testWidgets(
      'shared view rules, cancel, origin undo and stale peer draft at $width',
      (t) async {
        t.view.physicalSize = Size(width, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final c = await DatasetController.open(
          core: NativeDatasetCore(),
          store: MemoryStore(),
          objectId: '1c929539-049f-49ab-92e1-d0a9c5b51384',
          syncInterval: null,
        );
        await c.addRow(cells: {'title': 'Muse A'});
        await c.addRow(cells: {'title': 'Other B'});
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DatasetSurface(controller: c, title: "共享视图"),
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
        var inputs = find.byType(TextFormField);
        expect(inputs, findsOneWidget);
        await t.enterText(inputs, 'Muse A');
        await tap(find.byType(DropdownButtonFormField<String>).first);
        await tap(find.text('链接').last);
        expect(
          t
              .widget<EditableText>(find.byType(EditableText).first)
              .controller
              .text,
          isEmpty,
        );

        await tap(find.text('取消').last);
        expect(c.views.single.filters, isEmpty);
        expect(c.views.single.rows, hasLength(2));
        await tap(find.byKey(const ValueKey('dataset.filters')));
        await tap(find.byKey(const ValueKey('dataset.rules-add-filter')));
        await t.enterText(find.byType(TextFormField), 'Muse A');
        await tap(find.byKey(const ValueKey('dataset.rules-apply')));
        expect(c.views.single.rows, hasLength(1));
        expect(c.views.single.allRows, hasLength(2));
        expect(c.rowObjectIds, hasLength(2));
        await tap(find.byKey(const ValueKey('dataset.undo')));
        expect(c.views.single.rows, hasLength(2));
        await tap(find.byKey(const ValueKey('dataset.sorts')));
        await tap(find.byKey(const ValueKey('dataset.rules-add-sort')));
        // The shared view remains unchanged while the modal draft is open.
        expect(c.views.single.sorts, isEmpty);
        final old = c.views.single;
        await c.configureViewRules(
          old,
          filters: [],
          sorts: [
            {'id': 'peer-sort', 'field_id': 'title', 'condition': 1},
          ],
        );
        await t.pumpAndSettle();
        await tap(find.byKey(const ValueKey('dataset.rules-apply')));
        expect(
          find.byKey(const ValueKey('dataset.rules-error')),
          findsOneWidget,
        );
        expect(c.views.single.sorts.single['id'], 'peer-sort');
        await tap(find.text('取消').last);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await c.close();
      },
    );
  }
  testWidgets(
    'obsolete view history does not cross a command boundary and explains preserved peer content',
    (t) async {
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: 'c7732d76-1ced-4aa2-aa9d-54d7fd19752e',
        syncInterval: null,
      );
      await c.addRow(cells: {'title': 'Muse A'});
      Map<String, dynamic> rule(String text) => {
        'id': 'shared',
        'filter_type': 2,
        'field_id': 'title',
        'ty': 0,
        'condition': 2,
        'content': text,
      };
      await c.configureViewRules(
        c.views.single,
        filters: [rule('base')],
        sorts: [],
      );
      await c.configureViewRules(
        c.views.single,
        filters: [rule('local')],
        sorts: [],
      );
      final peer = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: c.objectId,
        initialBundle: c.bundle,
        syncInterval: null,
      );
      await peer.configureViewRules(
        peer.views.single,
        filters: [rule('peer')],
        sorts: [],
      );
      final original = peer.core.call({
        'action': 'syncObject',
        'handle': peer.handle,
        'objectId': peer.objectId,
      });
      await c.applyRealtimeUpdate(
        c.objectId,
        1,
        base64Decode(original['docState'] as String),
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DatasetSurface(controller: c, title: '共享视图'),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('dataset.undo')));
      await t.pumpAndSettle();
      expect(c.views.single.filters.single['content'], 'peer');
      expect(c.rowObjectIds, hasLength(1));
      expect(c.lastHistoryApplied, false);
      expect(find.text('这条修改已被协作者覆盖，当前内容已保留'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await peer.close();
      await c.close();
    },
  );
}
