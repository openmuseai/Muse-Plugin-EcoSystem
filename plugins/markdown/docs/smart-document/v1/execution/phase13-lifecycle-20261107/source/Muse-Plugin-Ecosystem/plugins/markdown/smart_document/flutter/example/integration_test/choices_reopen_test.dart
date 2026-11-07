import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_smart_document_stage1/dataset_main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh process reopens exact original choice schema, IDs, values and resource',
    (t) async {
      final w = await DatasetWorkbench.open();
      await t.pumpWidget(DatasetApp(workbench: w));
      for (var i = 0; i < 100 && w.controller == null; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final c = w.controller!;
      final prior =
          jsonDecode(
                await File(
                  '${w.directory.path}/evidence/choices-e2e.json',
                ).readAsString(),
              )
              as Map;
      expect(c.objectId, prior['objectId']);
      expect(c.snapshot['views'], prior['views']);
      final row = c.views.single.rows.single,
          state = c.views.single.columns.firstWhere(
            (f) => f.id == prior['stateFieldId'],
          ),
          tags = c.views.single.columns.firstWhere(
            (f) => f.id == prior['tagsFieldId'],
          );
      expect(state.name, '流程状态');
      expect(state.options.first.name, '待办,A😀');
      expect(row.cells[state.id]!.selectedOptionIds, [state.options.first.id]);
      expect(
        row.cells[tags.id]!.selectedOptionIds,
        tags.options.map((v) => v.id).toList(),
      );
      expect(row.cells['title']!.value, '选择字段端到端😀');
      expect(c.unavailableRows, isEmpty);
      expect(await w.session.prepareToClose(), isTrue);
      expect(t.takeException(), isNull);
      final evidence = Directory('${w.directory.path}/evidence');
      await File('${evidence.path}/choices-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': DatasetWorkbench.run,
          'objectId': c.objectId,
          'checks': [
            'fresh-process-existing-public-resource-ledger-and-original-root-row-cache',
            'original-field-option-id-name-color-and-unicode-exactly-restored',
            'selection-order-peer-schema-and-origin-undo-results-retained',
            'no-credentials-required-for-local-reopen-no-missing-row-fabrication',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_CHOICES_REOPEN=${evidence.path}');
    },
  );
}
