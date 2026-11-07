import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:muse_smart_document_stage1/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh process reopens the same table resource without Cloud credentials',
    (tester) async {
      expect(StageOneWorkbench.cloudEnabled, isFalse);
      final w = await StageOneWorkbench.open();
      final evidence = Directory('${w.directory.path}/evidence');
      final previous =
          jsonDecode(
                await File('${evidence.path}/table-e2e.json').readAsString(),
              )
              as Map;
      final context = await w.plugin.resourceConversationText(
        w.session.opened.content,
      );
      expect(context, contains('协作乙'));
      expect(context, contains('右下格：协作完成'));
      await tester.pumpWidget(StageOneApp(workbench: w));
      for (var i = 0; i < 100 && w.controller == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final c = w.controller!;
      expect(c.provider, isNull);
      expect(c.objectId, previous['objectId']);
      final table = c.resolveBlock(
        DocumentBlockReference.fromJson(
          Map<String, dynamic>.from(previous['table'] as Map),
        ),
      )!;
      final text = table.children.first.children.first;
      expect(text.id, previous['firstTextBlockId']);
      expect(text.delta!.toPlainText(), previous['firstText']);
      expect(
        text.delta!.toJson().first['attributes'],
        containsPair('bold', true),
      );
      expect(table.children[3].children.first.delta!.toPlainText(), '右下格：协作完成');
      expect(await w.session.prepareToClose(), isTrue);
      final report = {
        'status': 'passed',
        'platform': Platform.isIOS ? 'ios' : 'macos',
        'run': StageOneWorkbench.run,
        'objectId': c.objectId,
        'checks': [
          'fresh-process-no-cloud-provider-or-credentials',
          'same-sdk-resource-ledger-and-table-cell-identities',
          'exact-unicode-multiline-rich-text-and-peer-cells',
          'sdk-checkpoint-context-contains-collaborative-table-content',
        ],
      };
      await File(
        '${evidence.path}/table-reopen.json',
      ).writeAsString(jsonEncode(report));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await w.close();
      debugPrint('SMARTDOC_TABLE_REOPEN=${evidence.path}');
    },
  );
}
