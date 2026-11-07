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
    'fresh process reopens image, marks and authorized local bytes without cloud token',
    (tester) async {
      expect(StageOneWorkbench.cloudEnabled, isFalse);
      final w = await StageOneWorkbench.open();
      final evidence = Directory('${w.directory.path}/evidence');
      final previous =
          jsonDecode(
                await File('${evidence.path}/media-e2e.json').readAsString(),
              )
              as Map;
      await tester.pumpWidget(StageOneApp(workbench: w));
      for (var i = 0; i < 100 && w.controller == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final c = w.controller!;
      expect(c.provider, isNull);
      expect(c.objectId, previous['objectId']);
      final ref = DocumentBlockReference.fromJson(
        (previous['image'] as Map).cast<String, dynamic>(),
      );
      final image = c.resolveBlock(ref)!;
      expect(image.attributes['title'], '最终图片说明😀');
      expect(image.attributes['width'], 160.0);
      final media = w.plugin.mediaFor(w.session.record.identity)!;
      final bytes = await media.repository.read(
        AssetReference.fromJson(
          (image.attributes['asset'] as Map).cast<String, dynamic>(),
        ),
      );
      expect(bytes.length, greaterThan(0));
      expect(c.blocks.first.delta!.toPlainText(), previous['text']);
      expect(
        c.blocks.first.delta!.toJson().any(
          (r) =>
              (r['attributes'] as Map?)?['href'] ==
              'https://example.com/smart-document',
        ),
        isTrue,
      );
      expect(await w.session.prepareToClose(), isTrue);
      await File('${evidence.path}/media-reopen.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'checks': [
            'fresh-process-no-cloud-credentials',
            'same-sdk-image-block-and-property-registers',
            'private-scoped-cache-integrity-read',
            'exact-peer-text-and-hyperlink-mark',
          ],
        }),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await w.close();
      debugPrint('SMARTDOC_MEDIA_REOPEN=${evidence.path}');
    },
  );
}
