import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_smart_document_stage1/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh offline process reconstructs outline from original content checkpoint',
    (t) async {
      final w = await StageOneWorkbench.open(realtime: true);
      final evidence = Directory('${w.directory.path}/evidence');
      final prior =
          jsonDecode(
                await File('${evidence.path}/outline-e2e.json').readAsString(),
              )
              as Map;
      await t.pumpWidget(StageOneApp(workbench: w));
      for (var i = 0; i < 150 && w.controller == null; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final c = w.controller!;
      expect(c.objectId, prior['objectId']);
      expect(c.snapshot['outline'], prior['outline']);
      expect(c.outline.entries.last.reference.blockId, isNotEmpty);
      expect(w.plugin.realtimeFor(w.session.record.identity), isNull);
      expect(jsonEncode(await c.store.read()), isNot(contains('accessToken')));
      expect(t.takeException(), isNull);
      await File('${evidence.path}/outline-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'checks': [
            'same-resource-and-original-content-outline-restored',
            'fresh-kernel-derives-identical-hierarchy-without-network-or-credentials',
            'no-realtime-session-in-offline-reopen',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_OUTLINE_REOPEN=${evidence.path}');
    },
  );
}
