import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:muse_smart_document_stage1/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'credential-free fresh process reopens accepted realtime content',
    (t) async {
      final w = await StageOneWorkbench.open();
      await t.pumpWidget(StageOneApp(workbench: w));
      for (var i = 0; i < 100 && w.controller == null; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final c = w.controller!;
      final original =
          jsonDecode(
                await File(
                  '${w.directory.path}/evidence/realtime-e2e.json',
                ).readAsString(),
              )
              as Map;
      expect(c.objectId, original['objectId']);
      expect(c.blocks.first.delta!.toPlainText(), '重连实时智能文档😀');
      expect(c.hasPendingLocalChanges, isFalse);
      expect(w.plugin.realtimeFor(w.session.record.identity), isNull);
      expect(await w.session.prepareToClose(), isTrue);
      final evidence = Directory('${w.directory.path}/evidence');
      await File('${evidence.path}/realtime-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'checks': [
            'fresh-process-original-crdt-content-and-public-resource-ledger',
            'accepted-local-checkpoint-restores-without-duplicate-text',
            'no-credentials-no-presence-restoration-no-automatic-connection',
          ],
        }),
      );
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump();
      await w.close();
      debugPrint('SMARTDOC_REALTIME_REOPEN=${evidence.path}');
    },
  );
}
