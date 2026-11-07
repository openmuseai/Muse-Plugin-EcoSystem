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
    'fresh offline process preserves original board groups and independent row values',
    (t) async {
      final w = await EmbeddedWorkbench.open(realtime: true);
      final evidence = Directory('${w.document.directory.path}/evidence');
      final prior =
          jsonDecode(
                await File('${evidence.path}/board-e2e.json').readAsString(),
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
      final doc = w.document.controller!, c = w.dataset.controller!;
      expect(doc.objectId, prior['objectId']);
      expect(c.objectId, prior['datasetObjectId']);
      expect(c.snapshot['views'], prior['views']);
      expect(c.views.length, 2);
      expect(
        c.views.every((v) => v.columns.any((f) => f.id == prior['fieldId'])),
        true,
      );
      expect(
        c
            .readRow(prior['boardViewId'] as String, prior['rowId'] as String)
            .cells['title']!
            .value,
        '卡片详情中编辑',
      );
      expect(
        c.views
            .singleWhere((v) => v.id == prior['boardViewId'])
            .board!
            .groups
            .singleWhere((g) => g.id == prior['doneId'])
            .rowIds
            .toSet(),
        {prior['rowId'], prior['peerRowId']},
      );
      expect(
        w.dataset.plugin.realtimeFor(w.dataset.session.record.identity),
        isNull,
      );
      expect(jsonEncode(c.bundle), isNot(contains('accessToken')));
      expect(t.takeException(), isNull);
      await File('${evidence.path}/board-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'checks': [
            'same-document-dataset-and-grid-and-board-identities-after-fresh-process',
            'original-independent-rows-and-per-view-rules-survive-offline-checkpoint',
            'no-auth-provider-or-transient-presence-in-offline-reopen',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_BOARD_REOPEN=${evidence.path}');
    },
  );
}
