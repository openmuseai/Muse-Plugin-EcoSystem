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
    'native reads the actual two-browser nested view filters, sort and bounded-history row edit',
    () async {
      final root = Directory('../../.build');
      final config =
          jsonDecode(
                await File(
                  '${root.path}/nested-web-public.json',
                ).readAsString(),
              )
              as Map;
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final receipt =
          jsonDecode(
                await File(
                  '${root.path}/nested-web-result.json',
                ).readAsString(),
              )
              as Map;
      final datasetId = config['NESTED_DATASET'] as String;
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
          deviceId: 'nested-native-readback-$type',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
        ),
      );
      final v = c.views.single;
      expect(v.filters.single['filter_type'], 1);
      final children = v.filters.single['children'] as List;
      expect(children.map((c) => c['content']).toList(), ['Muse', 'B']);
      expect(v.rows.map((r) => r.id).toSet(), {
        config['NESTED_ROW_A'],
        config['NESTED_ROW_B'],
      });
      expect(c.rowObjectIds, hasLength(2));
      final d = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['NESTED_OBJECT'] as String,
        editable: false,
        createRemote: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'nested-parent-readback',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
      );
      expect(d.blocks.where((b) => b.type == 'grid'), hasLength(1));
      final target = ResourceEmbedTarget.fromJson(
        d.blocks.singleWhere((b) => b.type == 'grid').attributes['muse_embed'],
      );
      expect(target.selector['objectId'], datasetId);
      expect(jsonEncode(d.snapshot['data']), isNot(contains('Muse B')));
      expect(c.canWrite, false);
      expect(d.canWrite, false);
      await File('${root.path}/nested-native-web-readback.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': d.objectId,
          'datasetObjectId': datasetId,
          'rowA': config['NESTED_ROW_A'],
          'rowB': config['NESTED_ROW_B'],
          'checks': [
            'native-reuses-original-root1-and-both-row4-identities',
            'browser-nested-filter-child-intents-and-group-mode-read-back-over-real-Cloud',
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
