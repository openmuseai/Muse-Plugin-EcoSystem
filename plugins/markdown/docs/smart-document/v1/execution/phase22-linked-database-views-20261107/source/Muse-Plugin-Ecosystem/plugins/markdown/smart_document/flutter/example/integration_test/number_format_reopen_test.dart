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
    'fresh offline process preserves original numeric cells and independent resource',
    (t) async {
      final w = await EmbeddedWorkbench.open(realtime: true);
      final evidence = Directory('${w.document.directory.path}/evidence');
      final prior =
          jsonDecode(
                await File(
                  '${evidence.path}/number-format-e2e.json',
                ).readAsString(),
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
      expect(
        c.views.single.rows.single.cells[prior['fieldId']]!.numberInput,
        '42.125',
      );
      expect(
        w.dataset.plugin.realtimeFor(w.dataset.session.record.identity),
        isNull,
      );
      expect(jsonEncode(c.bundle), isNot(contains('accessToken')));
      expect(t.takeException(), isNull);
      await File('${evidence.path}/number-format-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': c.objectId,
          'checks': [
            'same-document-dataset-and-row-identities-after-fresh-process',
            'exact-original-number-and-options-survive-offline-checkpoint',
            'no-auth-provider-or-transient-presence-in-offline-reopen',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_NUMBER_FORMAT_REOPEN=${evidence.path}');
    },
  );
}
