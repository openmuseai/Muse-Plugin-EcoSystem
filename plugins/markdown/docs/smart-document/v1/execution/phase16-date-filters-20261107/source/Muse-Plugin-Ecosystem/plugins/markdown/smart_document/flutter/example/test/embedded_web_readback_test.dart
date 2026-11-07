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
    'native reads exact browser-edited independent child and unchanged original document locator',
    () async {
      final root = Directory('../../.build');
      final fixture =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final config =
          jsonDecode(
                await File(
                  '${root.path}/embedded-web-public.json',
                ).readAsString(),
              )
              as Map;
      final checks = <String>[];
      final watch = Stopwatch()..start();
      void trace(String step) {
        // ignore: avoid_print
        print('embedded readback ${watch.elapsedMilliseconds}ms $step');
      }
      trace('document open');
      final doc = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _Memory(),
        objectId: config['EMBEDDED_OBJECT'] as String,
        editable: false,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(fixture['origin'] as String),
          workspaceId: fixture['workspaceId'] as String,
          accessToken: () async =>
              fixture['users']['alice']['accessToken'] as String,
          deviceId: 'embedded-native-readback-doc',
        ),
        syncInterval: null,
      );
      trace('document opened');
      final block = doc.blocks.singleWhere((b) => b.type == 'grid');
      expect(
        ResourceEmbedTarget.fromJson(block.attributes['muse_embed']).key,
        ResourceEmbedTarget.fromJson(
          jsonDecode(config['EMBEDDED_TARGET'] as String),
        ).key,
      );
      expect(block.delta, isNull);
      checks.add(
        'native-original-document-keeps-exact-portable-locator-and-no-child-row-content',
      );
      trace('dataset open');
      final data = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: config['EMBEDDED_DATASET'] as String,
        editable: false,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(fixture['origin'] as String),
          workspaceId: fixture['workspaceId'] as String,
          accessToken: () async =>
              fixture['users']['alice']['accessToken'] as String,
          deviceId: 'embedded-native-readback-$type',
          binding: datasetBinding(type),
          collabType: type,
        ),
        syncInterval: null,
      );
      trace('dataset opened');
      expect(data.unavailableRows, isEmpty);
      final row = data.views.single.rows.single;
      expect(row.id, config['EMBEDDED_ROW']);
      expect(row.cells['title']!.value, '网页嵌入编辑😀');
      checks.add(
        'same-native-created-root-row-ids-and-real-browser-form-value-return-to-native',
      );
      expect(row.cells['done']!.value, true);
      checks.add('peer-checkbox-survives-browser-child-toolbar-undo-and-redo');
      trace('close dataset');
      await data.close();
      trace('close document');
      await doc.close();
      trace('closed');
      await File(
        '${root.path}/embedded-native-web-readback.json',
      ).writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': config['EMBEDDED_OBJECT'],
          'datasetObjectId': config['EMBEDDED_DATASET'],
          'rowId': row.id,
          'checks': checks,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
