import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_smart_document_stage1/main.dart';
import 'package:muse_smart_document_stage1/embedded_main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh credential-free process restores document locator and separately checkpointed dataset',
    (t) async {
      final w = await EmbeddedWorkbench.open();
      final evidence = Directory('${w.document.directory.path}/evidence');
      final prior =
          jsonDecode(
                await File('${evidence.path}/embedded-e2e.json').readAsString(),
              )
              as Map;
      await t.pumpWidget(StageOneApp(workbench: w.document));
      for (
        var i = 0;
        i < 150 &&
            (w.document.controller == null || w.dataset.controller == null);
        i++
      ) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final doc = w.document.controller!, data = w.dataset.controller!;
      expect(doc.objectId, prior['objectId']);
      expect(data.objectId, prior['datasetObjectId']);
      expect(
        doc.blocks.firstWhere((b) => b.type == 'grid').id,
        prior['blockId'],
      );
      expect(w.target.toJson(), prior['target']);
      expect(data.views.single.rows.single.id, prior['rowId']);
      expect(data.views.single.rows.single.cells['title']!.value, '协作者更新');
      expect(t.takeException(), isNull);
      await File('${evidence.path}/embedded-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': data.objectId,
          'checks': [
            'fresh-public-resource-ledgers-preserve-distinct-document-dataset-identities',
            'exact-original-grid-reference-view-and-row-identity-restored',
            'independent-resource-checkpoint-retains-peer-value-without-credentials',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_EMBEDDED_REOPEN=${evidence.path}');
    },
  );
}
