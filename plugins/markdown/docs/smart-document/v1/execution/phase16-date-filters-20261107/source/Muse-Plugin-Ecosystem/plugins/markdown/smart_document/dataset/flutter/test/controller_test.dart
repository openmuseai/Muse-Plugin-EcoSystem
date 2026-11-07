import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';

import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'original dataset/row values persist through a neutral store and stale drafts are refused',
    () async {
      final dir = await Directory.systemTemp.createTemp('muse-dataset-');
      final store = FileSnapshotStore(File('${dir.path}/dataset.json'));
      const id = '902301de-0bed-4023-815a-b385a69791b1';
      var c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: store,
        objectId: id,
        syncInterval: null,
      );
      final rowId = await c.addRow(cells: {'title': '同源数据😀', 'done': true});
      final view = c.views.single;
      final row = view.rows.single;
      final field = view.columns.firstWhere((f) => f.id == 'title');
      final hash = row.cells['title']!.hash;
      await c.setCell(row, field, '修改', expectedHash: hash);
      await expectLater(
        c.setCell(row, field, '过期草稿', expectedHash: hash),
        throwsA(isA<DatasetFailure>()),
      );
      await c.close();
      c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: store,
        objectId: id,
        editable: false,
        syncInterval: null,
      );
      expect(c.views.single.rows.single.id, rowId);
      expect(c.views.single.rows.single.cells['title']!.value, '修改');
      expect(c.canWrite, isFalse);
      await expectLater(c.addRow(), throwsA(isA<DatasetFailure>()));
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'write completion never marks a newer local revision saved or overlaps snapshot writes',
    () async {
      final store = MemoryStore();
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: store,
        objectId: '902301de-0bed-4023-815a-b385a69791b2',
        syncInterval: null,
      );
      final hold = Completer<void>();
      store.gate = hold;
      store.entered = Completer<void>();
      final first = c.addRow(cells: {'title': '第一行'});
      await store.entered!.future;
      final second = c.addRow(cells: {'title': '第二行'});
      expect(c.saveState, DatasetSaveState.dirty);
      expect(store.active, 1);
      hold.complete();
      await Future.wait([first, second]);
      expect(store.maxActive, 1);
      expect(c.saveState, DatasetSaveState.saved);
      await c.close();
      final reopened = await DatasetController.open(
        core: NativeDatasetCore(),
        store: store,
        objectId: '902301de-0bed-4023-815a-b385a69791b2',
        syncInterval: null,
      );
      expect(reopened.views.single.rows, hasLength(2));
      await reopened.close();
    },
  );
  test(
    'root publishing freezes dependency graph while editing stays available during row IO',
    () async {
      final core = TracedCore();
      final cloud = FakeCloud(core);
      final store = MemoryStore();
      final c = await DatasetController.open(
        core: core,
        store: store,
        objectId: '902301de-0bed-4023-815a-b385a69791b3',
        providerFactory: cloud.provider,
        createRemote: true,
        syncInterval: null,
      );
      expect(c.syncState, DatasetSyncState.accepted);
      final row1 = await c.addRow(cells: {'title': '第一行'});
      final entered = Completer<void>(), release = Completer<void>();
      String? frozen;
      cloud.beforeRead = (id, type) async {
        if (type == 4 && id == row1 && !entered.isCompleted) {
          frozen = core.lastRootBody;
          entered.complete();
          await release.future;
        }
      };
      final exchange = c.synchronize();
      await entered.future;
      final row2 = await c.addRow(cells: {'title': '网络等待期间新增'});
      release.complete();
      await exchange;
      expect(cloud.initialized, contains(row1));
      expect(cloud.initialized, isNot(contains(row2)));
      expect(cloud.rootRequests.last, frozen);
      expect(c.syncState, DatasetSyncState.pending);
      await c.synchronize();
      expect(cloud.initialized, contains(row2));
      expect(c.syncState, DatasetSyncState.accepted);
      final writes = store.writes;
      await c.synchronize();
      expect(
        store.writes,
        writes,
        reason: 'Unchanged exchanges do not rewrite the cache',
      );
      await c.close();
    },
  );
  test(
    'previously observed missing root never silently recreates on retry or reopen',
    () async {
      final core = TracedCore();
      final cloud = FakeCloud(core);
      final store = MemoryStore();
      const id = '902301de-0bed-4023-815a-b385a69791b4';
      var c = await DatasetController.open(
        core: core,
        store: store,
        objectId: id,
        providerFactory: cloud.provider,
        createRemote: true,
        syncInterval: null,
      );
      cloud.states.remove(id);
      final creates = cloud.initialized.length;
      await c.synchronize();
      expect(c.syncState, DatasetSyncState.removed);
      expect(c.canWrite, isFalse);
      await c.close();
      c = await DatasetController.open(
        core: core,
        store: store,
        objectId: id,
        providerFactory: cloud.provider,
        createRemote: true,
        syncInterval: null,
      );
      expect(c.syncState, DatasetSyncState.removed);
      expect(cloud.initialized, hasLength(creates));
      await c.close();
    },
  );
  test(
    'observed remote row is never recreated after deletion, retry or process reopen',
    () async {
      final core = TracedCore(), store = MemoryStore();
      final cloud = FakeCloud(core);
      const id = '902301de-0bed-4023-815a-b385a69791b5';
      var c = await DatasetController.open(
        core: core,
        store: store,
        objectId: id,
        providerFactory: cloud.provider,
        createRemote: true,
        syncInterval: null,
      );
      final row = await c.addRow(cells: {'title': '不能静默复活'});
      await c.synchronize();
      final old = cloud.states.remove(row)!;
      final creates = cloud.initialized.length;
      await c.synchronize();
      expect(c.unavailableRows, {row});
      expect(c.canWrite, isFalse);
      await c.synchronize();
      expect(cloud.initialized.length, creates);
      await c.close();
      c = await DatasetController.open(
        core: core,
        store: store,
        objectId: id,
        providerFactory: cloud.provider,
        createRemote: true,
        syncInterval: null,
      );
      expect(c.unavailableRows, {row});
      expect(c.canWrite, isFalse);
      expect(cloud.initialized.length, creates);
      cloud.states[row] = old;
      await c.synchronize();
      expect(c.unavailableRows, isEmpty);
      expect(c.canWrite, isTrue);
      expect(c.views.single.rows.single.cells['title']!.value, '不能静默复活');
      await Future.wait([c.close(), c.close()]);
    },
  );
}
