import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_smart_document_stage1/main.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh offline process reconstructs formula from original content checkpoint',
    (t) async {
      final w = await StageOneWorkbench.open(realtime: true);
      final evidence = Directory('${w.directory.path}/evidence');
      final prior =
          jsonDecode(
                await File('${evidence.path}/formula-e2e.json').readAsString(),
              )
              as Map;
      await t.pumpWidget(StageOneApp(workbench: w));
      for (var i = 0; i < 150 && w.controller == null; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final c = w.controller!;
      expect(c.objectId, prior['objectId']);
      expect(c.snapshot['data'], prior['data']);
      expect(
        c
            .captureFormula(
              DocumentBlockReference(
                objectId: c.objectId,
                blockId: prior['formulaId'] as String,
              ),
            )
            .formula,
        prior['formula'],
      );
      expect(w.plugin.realtimeFor(w.session.record.identity), isNull);
      expect(jsonEncode(await c.store.read()), isNot(contains('accessToken')));
      expect(t.takeException(), isNull);
      await File('${evidence.path}/formula-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'checks': [
            'same-resource-and-original-content-formula-restored',
            'fresh-kernel-derives-identical-formula-source-without-network-or-credentials',
            'no-realtime-session-in-offline-reopen',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_FORMULA_REOPEN=${evidence.path}');
    },
  );
}
