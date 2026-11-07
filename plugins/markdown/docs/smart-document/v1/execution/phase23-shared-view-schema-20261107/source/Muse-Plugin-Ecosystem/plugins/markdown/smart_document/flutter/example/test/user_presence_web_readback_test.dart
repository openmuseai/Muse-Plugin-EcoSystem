import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements SnapshotStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
  }
}

class _DocumentMemory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'native reads the actual two-browser users view filters, sort and bounded-history row edit',
    () async {
      final root = Directory('../../.build');
      final config =
          jsonDecode(
                await File('${root.path}/users-web-public.json').readAsString(),
              )
              as Map;
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final receipt =
          jsonDecode(
                await File('${root.path}/users-web-result.json').readAsString(),
              )
              as Map;
      final datasetId = config['USERS_DATASET'] as String;
      expect(receipt['datasetObjectId'], datasetId);
      expect(receipt['checks'], hasLength(20));
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: datasetId,
        editable: false,
        syncInterval: null,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'users-native-readback-$type',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
        ),
      );
      final v = c.views.single;
      expect(v.rows, hasLength(1));
      expect(v.rows.single.id, config['USERS_ROW']);
      expect(receipt['uid'], config['USERS_ALICE_UID']);
      expect((receipt['metrics'] as List).map((m) => m['users']).toList(), [
        2,
        2,
        1,
        1,
        2,
      ]);
      expect(
        (receipt['metrics'] as List).map((m) => m['remotePositions']).toList(),
        [3, 2, 1, 0, 1],
      );
      expect(jsonEncode(c.bundle), isNot(contains('muse.dataset.presence')));
      final d = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['USERS_OBJECT'] as String,
        editable: false,
        createRemote: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'users-parent-readback',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
      );
      expect(d.blocks.where((b) => b.type == 'grid'), hasLength(1));
      final target = ResourceEmbedTarget.fromJson(
        d.blocks.singleWhere((b) => b.type == 'grid').attributes['muse_embed'],
      );
      expect(target.selector['objectId'], datasetId);
      expect(
        jsonEncode(d.snapshot['data']),
        isNot(contains('muse.document.presence')),
      );
      expect(c.canWrite, false);
      expect(d.canWrite, false);
      await File('${root.path}/users-native-web-readback.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': d.objectId,
          'datasetObjectId': datasetId,
          'rowId': config['USERS_ROW'],
          'checks': [
            'native-reuses-original-document-root1-and-row4-identities',
            'browser-user-position-metrics-match-native-authenticated-UID-oracle',
            'native-parent-retains-only-generic-resource-locator',
            'fresh-reader-is-readonly-and-filter-independent-dependencies-preserved',
          ],
        }),
      );
      await c.close();
      await d.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
