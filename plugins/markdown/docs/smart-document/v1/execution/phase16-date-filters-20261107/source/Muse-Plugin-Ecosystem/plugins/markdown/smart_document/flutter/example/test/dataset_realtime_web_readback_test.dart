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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'native reads the two-browser original database update, dynamic row and scoped redo result',
    () async {
      final root = Directory('../../.build');
      final f =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final config =
          jsonDecode(
                await File(
                  '${root.path}/dataset-realtime-web-public.json',
                ).readAsString(),
              )
              as Map;
      final receipt =
          jsonDecode(
                await File(
                  '${root.path}/dataset-realtime-web-result.json',
                ).readAsString(),
              )
              as Map;
      final peer =
          jsonDecode(
                await File(
                  '${root.path}/dataset-realtime-web-peer.json',
                ).readAsString(),
              )
              as Map;
      expect(receipt['status'], 'passed');
      expect(peer['status'], 'passed');
      expect(peer['newRowId'], receipt['newRowId']);
      final doc = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _Memory(),
        objectId: receipt['objectId'] as String,
        editable: false,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(f['origin'] as String),
          workspaceId: f['workspaceId'] as String,
          accessToken: () async => f['users']['alice']['accessToken'] as String,
          deviceId: 'dataset-rt-native-readback-doc',
        ),
        syncInterval: null,
      );
      expect(
        ResourceEmbedTarget.fromJson(
          doc.blocks
              .singleWhere((b) => b.type == 'grid')
              .attributes['muse_embed'],
        ).key,
        ResourceEmbedTarget.fromJson(
          jsonDecode(config['DATASET_REALTIME_TARGET'] as String),
        ).key,
      );
      final checks = <String>[
        'same-native-document-structure-and-database-resource-reference-preserved',
      ];
      final data = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: receipt['datasetObjectId'] as String,
        editable: false,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(f['origin'] as String),
          workspaceId: f['workspaceId'] as String,
          accessToken: () async => f['users']['alice']['accessToken'] as String,
          deviceId: 'dataset-rt-native-readback-$type',
          binding: datasetBinding(type),
          collabType: type,
        ),
        syncInterval: null,
      );
      final rows = data.views.single.rows;
      expect(
        rows.singleWhere((r) => r.id == receipt['rowId']).cells['title']!.value,
        '网页协作者更新😀',
      );
      checks.add(
        'native-reads-same-original-row-edited-in-second-authenticated-browser-without-peer-overwrite',
      );
      expect(
        rows
            .singleWhere((r) => r.id == receipt['newRowId'])
            .cells['title']!
            .value,
        '网页新增记录',
      );
      expect(data.unavailableRows, isEmpty);
      expect(rows.length, 3);
      checks.add(
        'browser-created-independent-row-id-value-and-actual-child-undo-redo-result-return-to-native',
      );
      final nativeRows =
          (jsonDecode(config['DATASET_REALTIME_ROWS'] as String) as List)
              .cast<String>();
      expect(rows.map((r) => r.id).toSet(), {
        ...nativeRows,
        receipt['newRowId'],
      });
      expect(doc.snapshot['data'].toString(), isNot(contains('网页新增记录')));
      checks.add(
        'original-native-row-identities-retained-and-child-values-not-flattened-into-parent',
      );
      await data.close();
      await doc.close();
      await File(
        '${root.path}/dataset-realtime-native-web-readback.json',
      ).writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': receipt['objectId'],
          'datasetObjectId': receipt['datasetObjectId'],
          'rowId': receipt['rowId'],
          'newRowId': receipt['newRowId'],
          'checks': checks,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
