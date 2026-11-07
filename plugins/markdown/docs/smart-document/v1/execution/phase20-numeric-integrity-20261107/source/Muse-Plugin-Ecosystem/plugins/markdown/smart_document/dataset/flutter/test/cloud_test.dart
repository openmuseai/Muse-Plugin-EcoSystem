import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'original Cloud database type 1 and row type 4: two users, offline cells, undo, ACL and local reopen',
    () async {
      final fixture =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
              as Map;
      final dir = await Directory.systemTemp.createTemp('dataset-cloud-');
      final id = const Uuid().v4();
      final checks = <String>[];
      final core = NativeDatasetCore();
      DatasetProviderFactory providers(String user) =>
          (type) => AppFlowyObjectTransport(
            origin: Uri.parse(fixture['origin'] as String),
            workspaceId: fixture['workspaceId'] as String,
            deviceId: 'dataset-$user-$type',
            accessToken: () async =>
                fixture['users'][user]['accessToken'] as String,
            binding: datasetBinding(type),
            collabType: type,
          );
      final aliceStore = FileSnapshotStore(File('${dir.path}/alice.json'));
      final a = await DatasetController.open(
        core: core,
        store: aliceStore,
        objectId: id,
        providerFactory: providers('alice'),
        createRemote: true,
        syncInterval: null,
      );
      expect(
        a.syncState,
        DatasetSyncState.accepted,
        reason: '${a.syncFailure}',
      );
      final rowId = await a.addRow(
        cells: {'title': '数据集甲😀', 'done': false, 'url': 'https://example.com'},
      );
      await a.synchronize();
      expect(
        a.syncState,
        DatasetSyncState.accepted,
        reason: '${a.syncFailure}',
      );
      checks.add(
        'original-cloud-database-and-independent-row-created-under-types-1-and-4',
      );
      final b = await DatasetController.open(
        core: core,
        store: FileSnapshotStore(File('${dir.path}/bob.json')),
        objectId: id,
        providerFactory: providers('bob'),
        syncInterval: null,
      );
      expect(
        b.syncState,
        DatasetSyncState.accepted,
        reason: '${b.syncFailure}',
      );
      expect(b.views.single.rows.single.id, rowId);
      expect(b.views.single.rows.single.cells['title']!.value, '数据集甲😀');
      checks.add(
        'fresh-second-user-imports-original-root-before-opening-row-states-without-default-root-conflict',
      );
      DatasetRow row(DatasetController c) => c.views.single.rows.single;
      DatasetColumn column(DatasetController c, String field) =>
          c.views.single.columns.firstWhere((f) => f.id == field);
      a.pauseCollaboration(true);
      b.pauseCollaboration(true);
      await a.setCell(
        row(a),
        column(a, 'title'),
        '甲离线修改😀',
        expectedHash: row(a).cells['title']!.hash,
      );
      await b.setCell(
        row(b),
        column(b, 'done'),
        true,
        expectedHash: row(b).cells['done']!.hash,
      );
      a.pauseCollaboration(false);
      b.pauseCollaboration(false);
      for (var i = 0; i < 8; i++) {
        await a.synchronize();
        await b.synchronize();
      }
      expect(
        a.syncState,
        DatasetSyncState.accepted,
        reason: '${a.syncFailure}',
      );
      expect(
        b.syncState,
        DatasetSyncState.accepted,
        reason: '${b.syncFailure}',
      );
      expect(row(a).cells['title']!.value, '甲离线修改😀');
      expect(row(a).cells['done']!.value, true);
      expect(row(b).cells['title']!.value, '甲离线修改😀');
      expect(row(b).cells['done']!.value, true);
      checks.add(
        'two-authenticated-members-offline-independent-cell-edits-converge-without-replacing-row',
      );
      await a.history();
      for (var i = 0; i < 4; i++) {
        await a.synchronize();
        await b.synchronize();
      }
      expect(row(b).cells['title']!.value, '数据集甲😀');
      expect(row(b).cells['done']!.value, true);
      await a.history(redo: true);
      await a.synchronize();
      await b.synchronize();
      expect(row(b).cells['title']!.value, '甲离线修改😀');
      checks.add('original-row-origin-undo-redo-preserves-peer-checkbox');
      final viewer = await DatasetController.open(
        core: core,
        store: FileSnapshotStore(File('${dir.path}/viewer.json')),
        objectId: id,
        providerFactory: providers('bob'),
        editable: false,
        syncInterval: null,
      );
      expect(row(viewer).cells['done']!.value, true);
      await expectLater(viewer.addRow(), throwsA(isA<DatasetFailure>()));
      await viewer.close();
      await expectLater(
        DatasetController.open(
          core: core,
          store: FileSnapshotStore(File('${dir.path}/outsider.json')),
          objectId: id,
          providerFactory: providers('outsider'),
          syncInterval: null,
        ),
        throwsA(isA<AppFlowyTransportFailure>()),
      );
      final raw = providers('outsider')(4);
      final request = a.core.call({
        'action': 'syncObject',
        'handle': a.handle,
        'objectId': rowId,
      });
      await expectLater(
        raw.exchange(rowId, base64Decode(request['body'] as String)),
        throwsA(isA<AppFlowyTransportFailure>()),
      );
      raw.close();
      checks.add(
        'readonly-session-does-not-mutate-and-raw-nonmember-row-writes-are-rejected',
      );
      await a.close();
      await b.close();
      final reopened = await DatasetController.open(
        core: core,
        store: aliceStore,
        objectId: id,
        syncInterval: null,
      );
      expect(row(reopened).id, rowId);
      expect(row(reopened).cells['title']!.value, '甲离线修改😀');
      expect(row(reopened).cells['done']!.value, true);
      await reopened.close();
      checks.add(
        'neutral-local-store-reopens-same-root-row-identities-and-exact-peer-values-without-cloud',
      );
      await File('../../.build/dataset-cloud-result.json').writeAsString(
        jsonEncode({
          'status': 'passed-dataset-increment',
          'objectId': id,
          'rowId': rowId,
          'checks': checks,
          'limits': [
            'initial four-field/Grid profile only',
            'full-sync is not durable ACK',
            'live presence/share/history and full SiYuan semantics remain open',
          ],
        }),
      );
      await dir.delete(recursive: true);
    },
  );
}
