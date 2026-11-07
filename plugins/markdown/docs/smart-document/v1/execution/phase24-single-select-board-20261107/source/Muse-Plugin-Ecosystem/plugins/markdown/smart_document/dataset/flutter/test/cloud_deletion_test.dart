import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';

class TracedTransport implements CollaborationProvider {
  TracedTransport(this.inner, this.creates);
  final CollaborationProvider inner;
  final List<String> creates;
  @override
  CollaborationBinding get binding => inner.binding;
  @override
  Future<Uint8List?> readState(String id) => inner.readState(id);
  @override
  Future<Uint8List> exchange(String id, Uint8List body) =>
      inner.exchange(id, body);
  @override
  Future<void> initializeState(String id, Uint8List bytes) {
    creates.add(id);
    return inner.initializeState(id, bytes);
  }

  @override
  void close() => inner.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'deleted Cloud row cannot be silently recreated by live session or reopened cache',
    () async {
      final f =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
              as Map;
      final dir = await Directory.systemTemp.createTemp(
        'dataset-cloud-delete-',
      );
      final id = const Uuid().v4(), workspace = f['workspaceId'] as String;
      final token = f['users']['alice']['accessToken'] as String;
      final creates = <String>[];
      DatasetProviderFactory provider = (type) => TracedTransport(
        AppFlowyObjectTransport(
          origin: Uri.parse(f['origin'] as String),
          workspaceId: workspace,
          deviceId: 'dataset-delete-$type',
          accessToken: () async => token,
          binding: datasetBinding(type),
          collabType: type,
        ),
        creates,
      );
      final store = FileSnapshotStore(File('${dir.path}/cache.json'));
      var c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: store,
        objectId: id,
        providerFactory: provider,
        createRemote: true,
        syncInterval: null,
      );
      final row = await c.addRow(cells: {'title': '删除边界合成数据'});
      await c.synchronize();
      expect(c.syncState, DatasetSyncState.accepted);
      final wire = c.core.call({
        'action': 'syncObject',
        'handle': c.handle,
        'objectId': row,
      });
      final response = await http.delete(
        Uri.parse('${f['origin']}/api/workspace/$workspace/collab/$row'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'workspace_id': workspace, 'object_id': row}),
      );
      expect(response.statusCode, 200);
      expect((jsonDecode(response.body) as Map)['code'], 0);
      final direct = AppFlowyObjectTransport(
        origin: Uri.parse(f['origin'] as String),
        workspaceId: workspace,
        deviceId: 'dataset-delete-direct',
        accessToken: () async => token,
        binding: datasetBinding(4),
        collabType: 4,
      );
      final deleted = throwsA(
        isA<AppFlowyTransportFailure>().having(
          (e) => e.code,
          'code',
          'OBJECT_DELETED',
        ),
      );
      await expectLater(direct.readState(row), deleted);
      await expectLater(
        direct.exchange(row, base64Decode(wire['body'] as String)),
        deleted,
      );
      await expectLater(
        direct.initializeState(
          row,
          base64Decode(wire['encodedCollab'] as String),
        ),
        deleted,
      );
      direct.close();
      final before = creates.length;
      await c.synchronize();
      expect(
        c.canWrite,
        isFalse,
        reason:
            'A deleted original row must not appear editable from a stale live group',
      );
      expect(creates.length, before);
      await c.close();
      c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: store,
        objectId: id,
        providerFactory: provider,
        createRemote: true,
        syncInterval: null,
      );
      expect(c.canWrite, isFalse);
      expect(creates.length, before);
      expect(c.views.single.rows.single.cells['title']!.value, '删除边界合成数据');
      await c.synchronize();
      expect(creates.length, before);
      await c.close();
      await File(
        '../../.build/dataset-cloud-deletion-result.json',
      ).writeAsString(
        jsonEncode({
          'status': 'passed-row-deletion-slice',
          'objectId': id,
          'rowId': row,
          'checks': [
            'actual-cloud-soft-delete-observed-without-stale-editable-group',
            'live-session-no-row-recreation',
            'reopened-cache-no-row-recreation',
            'local-values-preserved-for-explicit-recovery',
            'direct-original-get-tombstone-not-absence',
            'raw-full-sync-rejected-before-queue',
            'raw-create-does-not-overwrite-tombstone',
          ],
        }),
      );
      await dir.delete(recursive: true);
    },
  );
}
