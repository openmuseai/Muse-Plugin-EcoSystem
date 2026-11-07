import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements SnapshotStore {
  Map<String, dynamic>? v;
  @override
  Future<Map<String, dynamic>?> read() async => v;
  @override
  Future<void> write(Map<String, dynamic> value) async {
    v = value;
  }
}

class _DocumentMemory implements DocumentStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> value) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'native reads the same original view schema and row cells',
    () async {
      final root = Directory('../../.build');
      final configFile = File('${root.path}/schema-view-web-public.json');
      final config = jsonDecode(await configFile.readAsString()) as Map;
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final preparing =
          Platform.environment['SCHEMA_VIEW_WEB_MODE'] == 'prepare';
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: config['SCHEMA_VIEW_DATASET'] as String,
        editable: false,
        syncInterval: null,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'schema-view-native-$type',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
        ),
      );
      final doc = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['SCHEMA_VIEW_OBJECT'] as String,
        editable: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'schema-view-native-doc',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
      );
      DatasetViewProjection view(String id) =>
          c.views.singleWhere((v) => v.id == id);
      final firstId = config['SCHEMA_VIEW_FIRST'] as String,
          nativeId = config['SCHEMA_VIEW_NATIVE_LINKED'] as String,
          temporaryId = config['SCHEMA_VIEW_NATIVE_TEMPORARY'] as String;
      expect(doc.objectId, isNot(c.objectId));
      expect(view(nativeId).rows.single.cells['title']!.value, '并发新增');
      final nativeField = config['SCHEMA_VIEW_NATIVE_FIELD'] as String;
      expect(
        c.views.every((v) => v.columns.any((f) => f.id == nativeField)),
        true,
      );
      expect(view(nativeId).rows.single.cells[nativeField]!.value, '字段并发值');

      if (preparing) {
        expect(c.views.length, 3);
        expect(view(firstId).rows.length, 2);
        expect(view(temporaryId).rows.length, 2);
        config['SCHEMA_VIEW_PARENT_DATA'] = jsonEncode(doc.snapshot['data']);
        config['SCHEMA_VIEW_NATIVE_ROW'] = view(nativeId).rows.single.id;
        await configFile.writeAsString(
          '${const JsonEncoder.withIndent("  ").convert(config)}\n',
        );
        await File('${root.path}/schema-view-web-prepare.json').writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': doc.objectId,
            'datasetObjectId': c.objectId,
            'checks': [
              'original-three-native-view-identities',
              'same-two-original-independent-rows',
              'parent-reference-baseline-from-original-cloud',
            ],
          }),
        );
      } else {
        final receipt =
            jsonDecode(
                  await File(
                    '${root.path}/schema-view-web-result.json',
                  ).readAsString(),
                )
                as Map;
        expect(receipt['checks'], hasLength(13));
        expect(receipt['objectId'], doc.objectId);
        expect(receipt['datasetObjectId'], c.objectId);
        expect(c.views.length, 5);
        expect(view(firstId).rows.length, 3);
        final web = view(receipt['webViewId'] as String),
            restored = view(receipt['temporaryViewId'] as String);
        expect(web.name, 'Web远端视图');
        expect(web.rows.single.id, receipt['peerRowId']);
        expect(web.rows.single.cells['title']!.value, 'Web新记录');
        final peerField = receipt['peerFieldId'] as String;
        expect(
          c.views.every(
            (v) =>
                v.columns.length == 5 &&
                v.columns.any((f) => f.id == peerField),
          ),
          true,
        );
        expect(web.rows.single.cells[peerField]!.value, 'Web字段值');
        expect(web.filters.length, 1);
        expect(view(nativeId).rows.single.id, config['SCHEMA_VIEW_NATIVE_ROW']);
        expect(view(nativeId).filters.length, 1);
        expect(restored.name, 'Web临时视图');
        expect(
          restored.rows.map((r) => r.id).toSet(),
          view(firstId).rows.map((r) => r.id).toSet(),
        );
        expect(
          c.bundle['objects'].where((o) => o['collabType'] == 1).length,
          1,
        );
        expect(
          c.bundle['objects'].where((o) => o['collabType'] == 4).length,
          3,
        );
        expect(
          jsonEncode(doc.snapshot['data']),
          config['SCHEMA_VIEW_PARENT_DATA'],
        );
        expect(jsonEncode(c.bundle), isNot(contains('accessToken')));
        await File(
          '${root.path}/schema-view-native-web-readback.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': doc.objectId,
            'datasetObjectId': c.objectId,
            'webViewId': web.id,
            'temporaryViewId': restored.id,
            'peerRowId': receipt['peerRowId'],
            'peerFieldId': receipt['peerFieldId'],
            'checks': [
              'same-original-native-browser-document-dataset-and-native-view-identities',
              'concurrent-new-row-survives-in-original-membership-without-row-copies',
              'native-and-web-filters-remain-independent-on-same-records',
              'native-reads-actual-web-stable-view-name-and-restored-view-id',
              'parent-reference-retains-original-content',
              'readonly-native-checkpoint-has-no-credential',
              'original-global-field-ids-and-independent-row-cell-values-survive-cross-platform-schema-race',
            ],
          }),
        );
      }
      await c.close();
      await doc.close();
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
