import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

const object = 'c616723b-8301-412f-ac6c-3688cb9a271c';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'root/row wire boundary fences unknown objects, missing dependencies, and original row ownership',
    () async {
      final a = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: object,
        syncInterval: null,
      );
      final b = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: object,
        initialBundle: a.bundle,
        syncInterval: null,
      );
      final id = await b.addRow(cells: {'title': '远端独立行😀'});
      final root = b.realtimeObjectState(object),
          row = b.realtimeObjectState(id);
      expect(root['collabType'], 1);
      expect(row['collabType'], 4);
      expect(base64Decode(root['stateVector'] as String), isNotEmpty);
      await expectLater(
        a.applyRealtimeUpdate(id, 4, base64Decode(row['docState'] as String)),
        throwsA(isA<DatasetFailure>()),
      );
      await expectLater(
        a.applyRealtimeUpdate(
          object,
          4,
          base64Decode(root['docState'] as String),
        ),
        throwsA(isA<DatasetFailure>()),
      );
      await a.applyRealtimeUpdate(
        object,
        1,
        base64Decode(root['docState'] as String),
      );
      expect(a.rowObjectIds, {id});
      expect(a.unavailableRows, {id});
      expect(a.canWrite, isFalse);
      expect(a.views.single.rows.single.loaded, isFalse);
      final foreign = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: '253c8f0f-4094-4e2f-b461-0e3061cde0d7',
        syncInterval: null,
      );
      await foreign.command({
        'op': 'addRow',
        'rowId': id,
        'cells': {'title': '不能污染另一个数据库'},
      });
      await expectLater(
        a.applyRealtimeUpdate(
          id,
          4,
          base64Decode(foreign.realtimeObjectState(id)['docState'] as String),
        ),
        throwsA(isA<DatasetFailure>()),
      );
      expect(a.views.single.rows.single.loaded, isFalse);
      await a.applyRealtimeUpdate(
        id,
        4,
        base64Decode(row['docState'] as String),
      );
      expect(a.canWrite, isTrue);
      expect(a.remoteObjectKnown(id), isTrue);
      expect(a.views.single.rows.single.cells['title']!.value, '远端独立行😀');
      final prior = jsonEncode(a.snapshot['views']);
      await a.applyRealtimeUpdate(
        id,
        4,
        base64Decode(row['docState'] as String),
      );
      expect(jsonEncode(a.snapshot['views']), prior);
      a.acceptRealtimeAccess(
        id: id,
        collabType: 4,
        canRead: false,
        canWrite: false,
        reason: 'denied',
      );
      expect(a.canRead, isFalse);
      expect(a.canWrite, isFalse);
      await b.history(); // remove only the original root's row reference
      await a.applyRealtimeUpdate(
        object,
        1,
        base64Decode(b.realtimeObjectState(object)['docState'] as String),
      );
      expect(a.rowObjectIds, isEmpty);
      expect(a.unavailableRows, isEmpty);
      expect(a.canRead, isTrue);
      expect(a.canWrite, isTrue);
      await foreign.close();
      await b.close();
      await a.close();
      await a.applyRealtimeUpdate(
        object,
        1,
        base64Decode(root['docState'] as String),
      );
      expect(
        () => a.realtimeObjectState(object),
        throwsA(isA<DatasetFailure>()),
      );
    },
  );
  test(
    'fresh authenticated read capabilities narrow Host writes; deletion and network pause cannot grant authority',
    () async {
      final a = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: object,
        syncInterval: null,
      );
      void access(bool read, bool write, {String reason = 'denied'}) =>
          a.acceptRealtimeAccess(
            id: object,
            collabType: 1,
            canRead: read,
            canWrite: write,
            reason: reason,
          );
      access(false, false);
      expect(a.canRead, isFalse);
      expect(a.canWrite, isFalse);
      access(true, false);
      expect(a.canRead, isTrue);
      expect(a.canWrite, isFalse);
      a.pauseCollaboration(true);
      a.pauseCollaboration(false);
      expect(a.canWrite, isFalse);
      await expectLater(a.addRow(), throwsA(isA<DatasetFailure>()));
      access(true, true);
      expect(a.canWrite, isTrue);
      access(false, false, reason: 'deleted');
      expect(a.canRead, isFalse);
      expect(a.syncState, DatasetSyncState.removed);
      access(true, true);
      expect(a.canWrite, isFalse);
      expect(a.syncState, DatasetSyncState.removed);
      await a.close();
      final readonly = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: object,
        editable: false,
        syncInterval: null,
      );
      readonly.acceptRealtimeAccess(
        id: object,
        collabType: 1,
        canRead: true,
        canWrite: true,
        reason: 'denied',
      );
      expect(readonly.canRead, isTrue);
      expect(readonly.canWrite, isFalse);
      await readonly.close();
    },
  );
}
