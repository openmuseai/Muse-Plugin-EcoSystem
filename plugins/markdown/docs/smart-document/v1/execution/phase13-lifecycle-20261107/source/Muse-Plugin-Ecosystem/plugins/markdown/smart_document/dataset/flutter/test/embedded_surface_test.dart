import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

ResourceEmbedTarget target(String view) => ResourceEmbedTarget(
  reference: ResourceReference(
    identity: ResourceIdentity(
      scope: 'test',
      source: 'local',
      workspace: 'test',
      mount: 'root',
      resource: 'dataset',
    ),
  ),
  surface: 'dataset.grid',
  selector: {
    'objectId': '143197bf-8e44-4c1c-a084-d28bd58087a7',
    'viewId': view,
  },
);
void main() {
  test(
    'pinned digest is part of ownership key even if identity and revision match',
    () async {
      var opens = 0;
      final registry = DatasetEmbedRegistry(
        open: (_) async {
          opens++;
          final c = await DatasetController.open(
            core: NativeDatasetCore(),
            store: MemoryStore(),
            objectId: '143197bf-8e44-4c1c-a084-d28bd58087a7',
            editable: false,
            syncInterval: null,
          );
          return DatasetEmbedSession(
            controller: c,
            title: '历史数据库',
            close: c.close,
          );
        },
      );
      ResourceEmbedTarget pin(String digest) {
        final t = target('view');
        return ResourceEmbedTarget(
          reference: ResourceReference.fromJson({
            ...t.reference.toJson(),
            'version': {'revision': 'same-revision', 'digest': digest},
          }),
          surface: t.surface,
          selector: t.selector,
        );
      }

      final a = pin('a' * 64), b = pin('b' * 64);
      final first = await registry.acquire(a),
          second = await registry.acquire(b);
      expect(opens, 2);
      expect(identical(first.controller, second.controller), isFalse);
      await registry.release(a);
      await registry.release(b);
      await registry.close();
    },
  );
  testWidgets(
    'same resource shares one mutable session; explicit missing view never redirects; parent readonly narrows child',
    (t) async {
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: '143197bf-8e44-4c1c-a084-d28bd58087a7',
        syncInterval: null,
      );
      await c.addRow(cells: {'title': '独立记录'});
      var opens = 0, closes = 0;
      final registry = DatasetEmbedRegistry(
        open: (_) async {
          opens++;
          return DatasetEmbedSession(
            controller: c,
            title: '项目数据库',
            close: () async {
              closes++;
              await c.close();
            },
          );
        },
      );
      final valid = target(c.views.single.id), missing = target('deleted-view');
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Builder(
                    builder: (ctx) => registry.build(
                      ctx,
                      valid,
                      const ResourceEmbedPolicy(allowEditing: false),
                    ),
                  ),
                ),
                Expanded(
                  child: Builder(
                    builder: (ctx) => registry.build(
                      ctx,
                      missing,
                      const ResourceEmbedPolicy(allowEditing: true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(opens, 1);
      expect(find.text('独立记录'), findsOneWidget);
      expect(find.text('指定视图不可用，原引用保留'), findsOneWidget);
      final add = find.byKey(const ValueKey('dataset.add-row'));
      for (final e in add.evaluate()) {
        expect((e.widget as TextButton).onPressed, isNull);
      }
      expect(c.canWrite, isTrue); // parent did not mutate independent authority
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      expect(closes, 1);
      await registry.close();
      expect(closes, 1);
    },
  );
  testWidgets('historical parent never calls a live resource resolver', (
    t,
  ) async {
    var opens = 0;
    final registry = DatasetEmbedRegistry(
      open: (_) async {
        opens++;
        throw StateError('must not open');
      },
    );
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => registry.build(
              ctx,
              target('view'),
              const ResourceEmbedPolicy(allowEditing: false, allowLive: false),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(opens, 0);
    expect(find.text('历史文档中的数据库引用未连接实时内容'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await registry.close();
  });
  test(
    'failed close retains ownership and explicit retry flushes it before another opener',
    () async {
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: '143197bf-8e44-4c1c-a084-d28bd58087a7',
        syncInterval: null,
      );
      var attempts = 0, opens = 0;
      final registry = DatasetEmbedRegistry(
        open: (_) async {
          opens++;
          return DatasetEmbedSession(
            controller: c,
            title: '数据库',
            close: () async {
              if (++attempts == 1) throw StateError('disk unavailable');
              await c.close();
            },
          );
        },
      );
      final t = target(c.views.single.id);
      await registry.acquire(t);
      await expectLater(registry.release(t), throwsStateError);
      await expectLater(registry.acquire(t), throwsStateError);
      expect(opens, 1);
      await registry.close();
      expect(attempts, 2);
    },
  );
}
