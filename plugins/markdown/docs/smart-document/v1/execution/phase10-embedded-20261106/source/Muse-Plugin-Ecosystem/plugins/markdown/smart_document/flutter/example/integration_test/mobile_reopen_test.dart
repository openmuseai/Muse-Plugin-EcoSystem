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
    'fresh process reopens previous mobile SDK resource and CRDT cache',
    (tester) async {
      final w = await StageOneWorkbench.open();
      final content = await w.plugin.resourceConversationText(
        w.session.opened.content,
      );
      expect(content, contains('移动智能文档😀'));
      await tester.pumpWidget(StageOneApp(workbench: w));
      for (var i = 0; i < 100 && w.controller == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final c = w.controller!;
      expect(c.failure, isNull);
      expect(
        c.blocks.first.delta!.toPlainText(),
        '移动智能文档😀',
        reason: 'Process restart must preserve exact text without duplication',
      );
      expect(c.blocks.first.type, 'numbered_list');
      expect(c.blocks.first.attributes['align'], 'center');
      expect(
        c.blocks.first.delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      expect(c.localSave, LocalSaveState.durable);
      expect(
        c.blocks.any(
          (node) =>
              node.type == 'code' &&
              node.delta?.toPlainText() == 'print("智能文档😀")\n# literal',
        ),
        isTrue,
      );
      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      expect(await w.session.prepareToClose(), isTrue);
      final report = {
        'status': 'passed',
        'platform': Platform.operatingSystem,
        'run': StageOneWorkbench.run,
        'objectId': c.objectId,
        'checks': [
          'fresh-app-process-existing-sdk-ledger-and-blobs',
          'rust-cache-reopens-with-list-alignment-unicode-and-range-marks',
          'code-block-literal-content-survives-fresh-process',
        ],
      };
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await w.close();
      await File(
        '${evidence.path}/mobile-reopen-result.json',
      ).writeAsString(jsonEncode(report));
      debugPrint('SMARTDOC_MOBILE_REOPEN_RESULT=${jsonEncode(report)}');
    },
  );
}
