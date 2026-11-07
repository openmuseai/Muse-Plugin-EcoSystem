import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_smart_document_stage1/dataset_main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('fresh process no cloud credential dataset SDK resource reopen', (
    t,
  ) async {
    expect(DatasetWorkbench.cloudEnabled, isFalse);
    final w = await DatasetWorkbench.open();
    final evidence = Directory('${w.directory.path}/evidence');
    final previous =
        jsonDecode(
              await File('${evidence.path}/dataset-e2e.json').readAsString(),
            )
            as Map;
    await t.pumpWidget(DatasetApp(workbench: w));
    for (var i = 0; i < 100 && w.controller == null; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final c = w.controller!;
    expect(c.objectId, previous['objectId']);
    expect(c.snapshot['views'], previous['views']);
    expect(c.views.single.rows.single.id, previous['rowId']);
    expect(c.canUndo, isFalse);
    expect(find.text('最终任务😀'), findsOneWidget);
    expect(await w.session.prepareToClose(), isTrue);
    await File('${evidence.path}/dataset-reopen.json').writeAsString(
      jsonEncode({
        'status': 'passed',
        'run': DatasetWorkbench.run,
        'objectId': c.objectId,
        'checks': [
          'fresh-process-no-cloud-credentials',
          'same-root-and-independent-row-addresses',
          'exact-values-field-order-and-types-from-public-resource-checkpoint',
          'actual-grid-render-and-empty-session-undo-history',
        ],
      }),
    );
    await t.pumpWidget(const SizedBox.shrink());
    await t.pump();
    await w.close();
    debugPrint('SMARTDOC_DATASET_REOPEN=${evidence.path}');
  });
}
