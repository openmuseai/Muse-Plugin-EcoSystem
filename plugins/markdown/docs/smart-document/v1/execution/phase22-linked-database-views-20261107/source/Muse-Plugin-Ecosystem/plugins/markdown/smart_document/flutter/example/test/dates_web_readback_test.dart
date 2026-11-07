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
    'native reads the actual two-browser date range, seconds and persisted field timezone',
    () async {
      final root = Directory('../../.build');
      final config =
          jsonDecode(
                await File('${root.path}/dates-web-public.json').readAsString(),
              )
              as Map;
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final receipt =
          jsonDecode(
                await File('${root.path}/dates-web-result.json').readAsString(),
              )
              as Map;
      final datasetId = config['DATES_DATASET'] as String,
          fieldId = config['DATES_FIELD'] as String;
      expect(receipt['datasetObjectId'], datasetId);
      expect(receipt['checks'], hasLength(9));
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
      final field = c.views.single.columns.singleWhere((f) => f.id == fieldId);
      expect(field.storageType, 2);
      expect(field.timezone, 'America/New_York');
      final row = c.views.single.rows.singleWhere(
        (r) => r.id == config['DATES_ROW'],
      );
      expect(row.cells[fieldId]!.value, {
        'start': '2026-11-18T09:10:11-05:00',
        'end': '2026-11-19T12:13:14-05:00',
        'includeTime': true,
        'isRange': true,
        'timezone': 'America/New_York',
      });
      final d = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['DATES_OBJECT'] as String,
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
      expect(jsonEncode(d.snapshot['data']), isNot(contains('2026-11-18')));
      expect(c.canWrite, false);
      expect(d.canWrite, false);
      await File('${root.path}/dates-native-web-readback.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': d.objectId,
          'datasetObjectId': datasetId,
          'fieldId': fieldId,
          'rowId': row.id,
          'checks': [
            'native-reuses-the-same-original-field2-and-row4-identities',
            'browser-date-range-seconds-and-flags-read-back-over-real-Cloud',
            'native-parent-retains-only-generic-resource-locator',
            'fresh-reader-is-readonly-and-keeps-explicit-field-timezone',
          ],
        }),
      );
      await c.close();
      await d.close();
    },
  );
}
