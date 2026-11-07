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
    'fresh process reopens independent realtime database content without transient presence or credentials',
    (t) async {
      final w = await EmbeddedWorkbench.open(realtime: true);
      final evidence = Directory('${w.document.directory.path}/evidence');
      final prior =
          jsonDecode(
                await File(
                  '${evidence.path}/date_filter-e2e.json',
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
      final doc = w.document.controller!, data = w.dataset.controller!;
      expect(doc.objectId, prior['objectId']);
      expect(data.objectId, prior['datasetObjectId']);
      expect(data.snapshot['views'], prior['views']);
      expect(data.unavailableRows, isEmpty);
      expect(
        w.dataset.plugin.realtimeFor(w.dataset.session.record.identity),
        isNull,
      );
      final fields = jsonEncode(data.bundle);
      expect(fields, isNot(contains('accessToken')));
      expect(fields, isNot(contains('muse.dataset.presence')));
      expect(t.takeException(), isNull);
      await File('${evidence.path}/date_filter-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': doc.objectId,
          'datasetObjectId': data.objectId,
          'checks': [
            'fresh-public-document-and-dataset-identities-and-original-views-restored',
            'date-filters-hidden-row-edits-and-original-seeds-survive-independent-checkpoints',
            'no-credential-required-no-transient-presence-or-socket-in-offline-reopen',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_DATE_FILTER_REOPEN=${evidence.path}');
    },
  );
}
