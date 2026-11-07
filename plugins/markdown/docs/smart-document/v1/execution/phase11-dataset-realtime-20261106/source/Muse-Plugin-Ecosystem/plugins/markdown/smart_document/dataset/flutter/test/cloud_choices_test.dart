import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:uuid/uuid.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'original choice metadata and independent cell values converge over actual root/row Cloud objects',
    () async {
      final f =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
              as Map;
      final id = const Uuid().v4(), core = NativeDatasetCore();
      DatasetProviderFactory providers(String user) =>
          (type) => AppFlowyObjectTransport(
            origin: Uri.parse(f['origin'] as String),
            workspaceId: f['workspaceId'] as String,
            accessToken: () async => f['users'][user]['accessToken'] as String,
            deviceId: 'dataset-choice-$user',
            collabType: type,
            binding: datasetBinding(type),
          );
      final store = MemoryStore();
      var a = await DatasetController.open(
        core: core,
        store: store,
        objectId: id,
        providerFactory: providers('alice'),
        createRemote: true,
        syncInterval: null,
      );
      await a.createField(
        '状态',
        'singleSelect',
        options: const [
          DatasetOptionDraft(name: '待办,A😀', color: 3),
          DatasetOptionDraft(name: '已完成', color: 6),
        ],
      );
      await a.createField(
        '标签',
        'multiSelect',
        options: const [
          DatasetOptionDraft(name: '研发', color: 8),
          DatasetOptionDraft(name: '设计', color: 0),
        ],
      );
      await a.addRow(cells: {'title': '选择字段协作'});
      DatasetColumn column(DatasetController c, String name) =>
          c.views.single.columns.firstWhere((v) => v.name == name);
      final state = column(a, '状态'),
          tags = column(a, '标签'),
          row = a.views.single.rows.single;
      await a.setCell(row, state, [
        state.options.first.id,
      ], expectedHash: row.cells[state.id]!.hash);
      await a.synchronize();
      expect(a.syncState, DatasetSyncState.accepted);
      final b = await DatasetController.open(
        core: core,
        store: MemoryStore(),
        objectId: id,
        providerFactory: providers('bob'),
        syncInterval: null,
      );
      final checks = <String>[];
      try {
        expect(
          column(b, '状态').options.map((v) => [v.id, v.name, v.color]),
          state.options.map((v) => [v.id, v.name, v.color]),
        );
        expect(b.views.single.rows.single.cells[state.id]!.value, '待办,A😀');
        checks.add(
          'original-type-option-id-name-color-and-comma-unicode-roundtrip',
        );
        final ar = a.views.single.rows.single, br = b.views.single.rows.single;
        await a.setCell(ar, column(a, '状态'), [
          state.options.last.id,
        ], expectedHash: ar.cells[state.id]!.hash);
        await b.setCell(
          br,
          column(b, '标签'),
          tags.options.map((v) => v.id).toList(),
          expectedHash: br.cells[tags.id]!.hash,
        );
        for (var i = 0; i < 4; i++) {
          await a.synchronize();
          await b.synchronize();
        }
        expect(a.snapshot['views'], b.snapshot['views']);
        checks.add(
          'actual-root-type-1-independent-row-type-4-cell-convergence',
        );
        await a.history();
        await a.synchronize();
        await b.synchronize();
        expect(a.views.single.rows.single.cells[state.id]!.value, '待办,A😀');
        expect(a.views.single.rows.single.cells[tags.id]!.value, ['研发', '设计']);
        checks.add('original-local-origin-undo-keeps-peer-choice-cell');
        final before = column(a, '状态'), staleRow = a.views.single.rows.single;
        await b.renameField(column(b, '状态'), '流程状态');
        await b.synchronize();
        await a.synchronize();
        await expectLater(
          a.setCell(staleRow, before, [
            state.options.last.id,
          ], expectedHash: staleRow.cells[state.id]!.hash),
          throwsA(
            isA<DatasetFailure>().having(
              (e) => e.code,
              'code',
              'FIELD_CHANGED',
            ),
          ),
        );
        checks.add('peer-schema-change-rejects-old-choice-draft');
        await a.close();
        a = await DatasetController.open(
          core: core,
          store: store,
          objectId: id,
          syncInterval: null,
        );
        expect(column(a, '流程状态').options.first.name, '待办,A😀');
        expect(
          a.views.single.rows.single.cells[tags.id]!.selectedOptionIds,
          tags.options.map((v) => v.id).toList(),
        );
        checks.add(
          'credential-free-cache-reopen-retains-original-option-and-cell-identities',
        );
        await File(
          '../../.build/dataset-choice-cloud-result.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': id,
            'checks': checks,
            'fullProductAcceptance': 'not-complete',
          }),
        );
      } finally {
        await b.close();
        await a.close();
      }
    },
  );
}
