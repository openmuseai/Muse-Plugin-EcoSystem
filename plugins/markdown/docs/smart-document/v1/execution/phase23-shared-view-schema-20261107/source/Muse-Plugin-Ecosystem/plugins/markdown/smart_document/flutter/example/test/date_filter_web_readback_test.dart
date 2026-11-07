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
    'native reads actual browser date filters, range and new-row edits from original Cloud objects',
    () async {
      final root = Directory('../../.build');
      final config =
          jsonDecode(
                await File(
                  '${root.path}/date_filter-web-public.json',
                ).readAsString(),
              )
              as Map;
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final receipt =
          jsonDecode(
                await File(
                  '${root.path}/date_filter-web-result.json',
                ).readAsString(),
              )
              as Map;
      final datasetId = config['DATE_FILTER_DATASET'] as String;
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
          deviceId: 'date_filter-native-readback-$type',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
        ),
      );
      final v = c.views.single;
      expect(v.filters.single['condition'], 7);
      expect(v.rows, hasLength(4));
      expect(v.allRows, hasLength(4));
      final fieldId = config['DATE_FILTER_FIELD'] as String;
      final row = c.readRow(v.id, config['DATE_FILTER_ROW'] as String);
      expect((row.cells[fieldId]!.value as Map)['start'], '2026-11-10');
      expect((row.cells[fieldId]!.value as Map)['end'], '2026-11-11');
      expect(
        v.rows.any(
          (r) => (r.cells[fieldId]!.value as Map)['start'] == '2026-11-11',
        ),
        true,
      );
      final d = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['DATE_FILTER_OBJECT'] as String,
        editable: false,
        createRemote: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'date_filter-parent-readback',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
      );
      expect(d.blocks.where((b) => b.type == 'grid'), hasLength(1));
      final target = ResourceEmbedTarget.fromJson(
        d.blocks.singleWhere((b) => b.type == 'grid').attributes['muse_embed'],
      );
      expect(target.selector['objectId'], datasetId);
      expect(jsonEncode(d.snapshot['data']), isNot(contains('2026-11-10')));
      expect(c.canWrite, false);
      expect(d.canWrite, false);
      await File(
        '${root.path}/date_filter-native-web-readback.json',
      ).writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': d.objectId,
          'datasetObjectId': datasetId,
          'rowId': config['DATE_FILTER_ROW'],
          'fieldId': config['DATE_FILTER_FIELD'],
          'checks': [
            'native-reuses-original-root1-and-four-row4-identities',
            'browser-shared-date-filter-range-and-new-row-read-back-over-real-Cloud',
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
