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
    'native prepares or reads the exact browser original numeric objects',
    () async {
      final root = Directory('../../.build');
      final configFile = File('${root.path}/number-format-web-public.json');
      final config = jsonDecode(await configFile.readAsString()) as Map;
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final preparing =
          Platform.environment['NUMBER_FORMAT_WEB_MODE'] == 'prepare';
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: config['NUMBER_FORMAT_DATASET'] as String,
        editable: false,
        syncInterval: null,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'number-format-native-$type',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
        ),
      );
      final doc = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['NUMBER_FORMAT_OBJECT'] as String,
        editable: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'number-format-native-doc',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
      );
      final fieldId = config['NUMBER_FORMAT_FIELD'] as String,
          row = c.views.single.rows.single;
      expect(row.id, config['NUMBER_FORMAT_ROW']);
      expect(doc.objectId, isNot(c.objectId));
      expect(c.views.single.columns.last.name, '远端预算');
      final format = (c.snapshot['views'][0]['columns'] as List)
          .cast<Map>()
          .firstWhere(
            (f) => f['id'] == fieldId,
          )['raw']['type_options']['1']['format'];
      if (preparing) {
        expect(row.cells[fieldId]!.numberInput, '42.125');
        expect(format, 1);
        config['NUMBER_FORMAT_PARENT_DATA'] = jsonEncode(doc.snapshot['data']);
        await configFile.writeAsString(
          '${const JsonEncoder.withIndent("  ").convert(config)}\n',
        );
        await File('${root.path}/number-format-web-prepare.json').writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': doc.objectId,
            'datasetObjectId': c.objectId,
            'checks': [
              'original-native-document-dataset-and-row-scope',
              'original-number-value-and-format-after-native-ui',
              'parent-content-baseline-from-original-cloud',
            ],
          }),
        );
      } else {
        final receipt =
            jsonDecode(
                  await File(
                    '${root.path}/number-format-web-result.json',
                  ).readAsString(),
                )
                as Map;
        expect(receipt['checks'], hasLength(12));
        expect(receipt['datasetObjectId'], c.objectId);
        expect(receipt['objectId'], doc.objectId);
        expect(
          row.cells[fieldId]!.numberInput,
          '12345678901234567890.12345678',
        );
        expect(row.cells[fieldId]!.value, r'$12,345,678,901,234,567,890.12');
        expect(format, 1);
        expect(
          jsonEncode(doc.snapshot['data']),
          config['NUMBER_FORMAT_PARENT_DATA'],
        );
        expect(jsonEncode(c.bundle), isNot(contains('accessToken')));
        await File(
          '${root.path}/number-format-native-web-readback.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': doc.objectId,
            'datasetObjectId': c.objectId,
            'rowId': row.id,
            'fieldId': fieldId,
            'checks': [
              'same-original-native-browser-object-identities',
              'original-Row4-retains-exact-28-digit-string',
              'original-format-metadata-and-parent-reference-stay-independent',
              'readonly-native-readback-has-no-credential-in-content',
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
