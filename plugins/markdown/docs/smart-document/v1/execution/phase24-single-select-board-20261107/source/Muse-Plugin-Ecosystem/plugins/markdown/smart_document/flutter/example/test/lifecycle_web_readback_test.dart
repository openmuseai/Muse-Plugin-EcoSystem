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
    'native reads actual browser lifecycle edit from the same original database and row',
    () async {
      final root = Directory('../../.build');
      final config =
          jsonDecode(
                await File(
                  '${root.path}/lifecycle-web-public.json',
                ).readAsString(),
              )
              as Map;
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final receipt =
          jsonDecode(
                await File(
                  '${root.path}/lifecycle-web-result.json',
                ).readAsString(),
              )
              as Map;
      final datasetId = config['LIFECYCLE_DATASET'] as String;
      expect(receipt['datasetObjectId'], datasetId);
      expect(receipt['checks'], hasLength(8));
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: datasetId,
        editable: false,
        syncInterval: null,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'date-native-readback-$type',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
        ),
      );
      final row = c.views.single.rows.singleWhere(
        (r) => r.id == config['LIFECYCLE_ROW'],
      );
      expect(row.cells['title']!.value, '浏览器恢复后的编辑');
      expect(
        (c.bundle['objects'] as List).map((v) => v['collabType']).toSet(),
        {1, 4},
      );
      final d = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['LIFECYCLE_OBJECT'] as String,
        editable: false,
        createRemote: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'dates-parent-readback',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
      );
      expect(d.blocks.where((b) => b.type == 'grid'), hasLength(1));
      final target = ResourceEmbedTarget.fromJson(
        d.blocks.singleWhere((b) => b.type == 'grid').attributes['muse_embed'],
      );
      expect(target.selector['objectId'], datasetId);
      expect(jsonEncode(d.snapshot['data']), isNot(contains('浏览器恢复后的编辑')));
      expect(c.canWrite, false);
      expect(d.canWrite, false);
      await File(
        '${root.path}/lifecycle-native-web-readback.json',
      ).writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': d.objectId,
          'datasetObjectId': datasetId,

          'rowId': row.id,
          'checks': [
            'native-reuses-the-same-independent-root1-and-row4-identities',
            'actual-browser-post-reopen-cell-edit-reads-back-over-real-Cloud',
            'native-parent-retains-only-generic-resource-locator',
            'fresh-native-reader-keeps-immutable-Host-readonly-floor',
          ],
        }),
      );
      await c.close();
      await d.close();
    },
  );
}
