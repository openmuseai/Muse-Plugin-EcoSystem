import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'native reads the browser edits of the original native-created choice objects',
    () async {
      final f =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
              as Map;
      final receipt =
          jsonDecode(
                await File(
                  '../../.build/choices-web-result.json',
                ).readAsString(),
              )
              as Map;
      final config =
          jsonDecode(
                await File(
                  '../../.build/choices-web-public.json',
                ).readAsString(),
              )
              as Map;
      expect(receipt['status'], 'passed');
      expect(receipt['objectId'], config['CHOICES_OBJECT']);
      final c = await DatasetController.open(
        core: NativeDatasetCore(),
        store: MemoryStore(),
        objectId: receipt['objectId'] as String,
        providerFactory: (type) => AppFlowyObjectTransport(
          origin: Uri.parse(f['origin'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          accessToken: () async => f['users']['alice']['accessToken'] as String,
          deviceId: 'native-choice-web-readback',
          collabType: type,
          binding: datasetBinding(type),
        ),
        syncInterval: null,
      );
      try {
        final row = c.views.single.rows.single;
        expect(row.id, receipt['rowId']);
        expect(
          row.loaded,
          isTrue,
          reason:
              'Row must be loaded: ${c.syncState}; ${c.syncFailure}; unavailable=${c.unavailableRows}',
        );
        final state = c.views.single.columns.firstWhere(
              (v) => v.id == config['CHOICES_STATE_FIELD'],
            ),
            tags = c.views.single.columns.firstWhere(
              (v) => v.id == config['CHOICES_TAGS_FIELD'],
            );
        expect(row.cells[state.id]!.value, '进行中');
        expect(row.cells[tags.id]!.value, ['质量']);
        final browserField = c.views.single.columns.firstWhere(
          (v) => v.name == '网页优先级',
        );
        expect(browserField.semanticType, 'singleSelect');
        expect(browserField.options.map((v) => v.name).toList(), ['紧急', '常规']);
        expect(state.options.first.name, '待办,A😀');
        expect(state.options.map((v) => v.color).toList(), [0, 1, 2]);
        expect(row.cells[state.id]!.selectedOptionIds, [state.options[1].id]);
        expect(row.cells[tags.id]!.selectedOptionIds, [tags.options.last.id]);
        await File(
          '../../.build/choices-native-web-readback.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'objectId': c.objectId,
            'rowId': row.id,
            'checks': [
              'actual-native-to-browser-to-native-same-root-and-row-object',
              'browser-created-original-select-field-reopens-through-native-reader',
              'native-reader-reopens-browser-single-and-peer-multi-cell',
              'stable-option-id-comma-name-and-color-survive-both-wasm-and-native',
              'browser-toolbar-origin-undo-result-read-from-original-cloud',
            ],
            'fullProductAcceptance': 'not-complete',
          }),
        );
      } finally {
        await c.close();
      }
    },
  );
}
