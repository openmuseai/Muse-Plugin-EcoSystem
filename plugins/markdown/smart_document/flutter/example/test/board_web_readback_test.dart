import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements SnapshotStore {
  @override
  Future<Map<String, dynamic>?> read() async => null;
  @override
  Future<void> write(Map<String, dynamic> value) async {}
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
    'native reads original board and grid identities after browser collaboration',
    () async {
      final root = Directory('../../.build'),
          file = File('../../.build/board-web-public.json');
      final config = jsonDecode(await file.readAsString()) as Map,
          fixture =
              jsonDecode(
                    await File('../../.build/e2e-fixture.json').readAsString(),
                  )
                  as Map;
      final prepare = Platform.environment['BOARD_WEB_MODE'] == 'prepare';
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: _Memory(),
        objectId: config['BOARD_DATASET'] as String,
        editable: false,
        syncInterval: null,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'board-native-$type',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
          binding: datasetBinding(type),
          collabType: type,
        ),
      );
      final doc = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _DocumentMemory(),
        objectId: config['BOARD_OBJECT'] as String,
        editable: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'board-native-doc',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
      );
      final first = config['BOARD_FIRST'] as String,
          board = config['BOARD_NATIVE'] as String,
          field = config['BOARD_FIELD'] as String,
          done = config['BOARD_DONE'] as String;
      final checks = <String>[];
      expect(c.views.singleWhere((v) => v.id == board).board!.ready, true);
      expect(
        c.readRow(first, config['BOARD_ROW'] as String).cells['title']!.value,
        '卡片详情中编辑',
      );
      checks.add('same-original-native-board-and-independent-row-values');
      if (prepare) {
        expect(c.views.length, 2);
        expect(c.views.every((v) => v.rows.length == 2), true);
        config['BOARD_PARENT_DATA'] = jsonEncode(doc.snapshot['data']);
        await file.writeAsString(
          '${const JsonEncoder.withIndent("  ").convert(config)}\n',
        );
        checks.add('fresh-parent-reference-baseline-from-cloud');
      } else {
        final receipt =
            jsonDecode(
                  await File(
                    '${root.path}/board-web-result.json',
                  ).readAsString(),
                )
                as Map;
        expect(receipt['checks'], hasLength(11));
        expect(receipt['objectId'], doc.objectId);
        expect(receipt['datasetObjectId'], c.objectId);
        checks.add('browser-receipt-identities-match-fresh-native-cloud-read');
        expect(c.views.length, 3);
        expect(c.views.every((v) => v.rows.length == 3), true);
        expect(
          c.views
              .map((v) => v.rows.map((r) => r.id).toSet())
              .every((ids) => ids.contains(receipt['webRowId'])),
          true,
        );
        checks.add('three-views-share-three-original-row-identities');
        final row = c.readRow(first, receipt['webRowId'] as String);
        expect(row.cells[field]!.selectedOptionIds, [done]);
        expect(row.cells[receipt['numberFieldId']]!.numberInput, '12.5');
        expect(row.cells['title']!.value, 'Web卡片详情');
        checks.add('peer-location-number-value-and-author-redo-persist');
        for (final v in c.views.where((v) => v.layout == 1)) {
          expect(
            v.board!.groups.singleWhere((g) => g.id == done).rowIds.length,
            3,
          );
        }
        checks.add('both-board-projections-use-original-option-ids');
        final objects = c.bundle['objects'] as List;
        expect(objects.length, 4);
        expect(objects.where((o) => o['collabType'] == 1).length, 1);
        expect(objects.where((o) => o['collabType'] == 4).length, 3);
        checks.add(
          'one-database-root-and-three-row-objects-without-card-copies',
        );
        expect(jsonEncode(doc.snapshot['data']), config['BOARD_PARENT_DATA']);
        checks.add('parent-document-reference-is-unchanged');
      }
      await File(
        '${root.path}/${prepare ? 'board-web-prepare' : 'p24-native-web-readback'}.json',
      ).writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'checks': checks,
        }),
      );
      await c.close();
      await doc.close();
    },
  );
}
