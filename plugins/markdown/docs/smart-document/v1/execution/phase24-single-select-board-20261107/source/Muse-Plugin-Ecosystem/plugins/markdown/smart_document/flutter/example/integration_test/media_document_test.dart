import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:muse_smart_document_stage1/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'SDK image and link UI, private bytes, concurrent edits and reopen checkpoint',
    (tester) async {
      final previous = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      addTearDown(
        () => WidgetController.hitTestWarningShouldBeFatal = previous,
      );
      expect(StageOneWorkbench.cloudEnabled, isTrue);
      final png = (await rootBundle.load(
        'assets/test-image.png',
      )).buffer.asUint8List();
      var pickerCalls = 0;
      final w = await StageOneWorkbench.open(
        imagePicker: () async {
          pickerCalls++;
          return PickedDocumentImage(png, 'test-image.png');
        },
      );
      await tester.pumpWidget(StageOneApp(workbench: w));
      Future<void> until(bool Function() ready) async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (ready()) return;
        }
        fail('Media UI/Cloud deadline exceeded');
      }

      await until(() => w.controller != null);
      bool decodedImage() => find
          .byType(RawImage)
          .evaluate()
          .any((e) => (e.widget as RawImage).image?.width == 32);
      final c = w.controller!;
      c.pauseCollaboration(true);
      final checks = <String>[];
      final mobile = Platform.isIOS;
      if (mobile) {
        await tester.tap(find.text('编辑'));
        await tester.pump();
      }
      await c.editor.apply(
        c.editor.transaction..insertText(c.blocks.first, 0, '超链接正文😀'),
      );
      await c.flush();
      final bob = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${w.directory.path}/bob.json')),
        objectId: c.objectId,
        initialDocState: c.snapshot['docState'] as String,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(StageOneWorkbench.origin),
          workspaceId: StageOneWorkbench.workspace,
          deviceId: 'media-bob',
          accessToken: () async => StageOneWorkbench.bobToken,
        ),
        syncInterval: null,
      );
      bob.pauseCollaboration(true);
      c.editor.selection = Selection.single(
        path: c.blocks.first.path,
        startOffset: 0,
        endOffset: 4,
      );
      await tester.pump();
      if (mobile) {
        await tester.tap(
          find.byKey(const ValueKey('smart-document.mobile.insert')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(find.text('超链接'));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(find.text('超链接'));
      } else {
        await tester.tap(find.byKey(const ValueKey('smart-document.link')));
      }
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('smart-document.link-dialog')),
        findsOneWidget,
      );
      // Apply a real peer update while the actual dialog retains its captured range.
      await bob.editor.apply(
        bob.editor.transaction..insertText(bob.blocks.first, 0, '协作前缀：'),
      );
      await bob.flush();
      bob.pauseCollaboration(false);
      await bob.synchronize();
      c.pauseCollaboration(false);
      await c.synchronize();
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('smart-document.link-address')),
        'https://example.com/smart-document',
      );
      await tester.tap(find.byKey(const ValueKey('smart-document.link-apply')));
      await until(
        () => find
            .byKey(const ValueKey('smart-document.link-dialog'))
            .evaluate()
            .isEmpty,
      );
      expect(c.blocks.first.delta!.toPlainText(), '协作前缀：超链接正文😀');
      final runs = c.blocks.first.delta!.toJson();
      expect(
        runs.any(
          (r) =>
              r['insert'] == '超链接正' &&
              (r['attributes'] as Map?)?['href'] ==
                  'https://example.com/smart-document',
        ),
        isTrue,
      );
      checks.add(
        'actual-link-dialog-relative-range-survives-peer-prefix-without-overwrite',
      );
      // Reopen the same addressed mark and exercise URL rejection without committing.
      c.editor.selection = Selection.single(
        path: c.blocks.first.path,
        startOffset: 5,
        endOffset: 9,
      );
      await tester.pump();
      if (mobile) {
        await tester.tap(
          find.byKey(const ValueKey('smart-document.mobile.insert')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.ensureVisible(find.text('超链接'));
        await tester.pump(const Duration(milliseconds: 150));
        await tester.tap(find.text('超链接'));
      } else {
        await tester.tap(find.byKey(const ValueKey('smart-document.link')));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('smart-document.link-address')),
        'javascript:alert(1)',
      );
      await tester.tap(find.byKey(const ValueKey('smart-document.link-apply')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('链接或选区无效，请检查后重试'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 300));
      checks.add(
        'actual-link-dialog-rejects-unsafe-url-and-keeps-existing-mark',
      );
      c.editor.selection = Selection.collapsed(
        Position(
          path: c.blocks.first.path,
          offset: c.blocks.first.delta!.length,
        ),
      );
      await tester.tap(
        find.byKey(
          ValueKey(
            mobile ? 'smart-document.mobile.insert' : 'smart-document.insert',
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('图片'));
      await until(() => c.blocks.any((n) => n.type == 'image'));
      expect(pickerCalls, 1);
      final image = c.blocks.firstWhere((n) => n.type == 'image');
      final ref = DocumentBlockReference(
        objectId: c.objectId,
        blockId: image.id,
      );
      final asset = AssetReference.fromJson(
        (image.attributes['asset'] as Map).cast<String, dynamic>(),
      );
      final bobAssets = CloudAssetRepository(
        origin: Uri.parse(StageOneWorkbench.origin),
        workspaceId: StageOneWorkbench.workspace,
        accessToken: () async => StageOneWorkbench.bobToken,
      );
      expect(await bobAssets.read(asset), png);
      bobAssets.close();
      await until(decodedImage);
      checks.add(
        'actual-insert-image-menu-original-renderer-and-second-user-private-bytes',
      );
      final menu = find.byKey(
        ValueKey('smart-document.image-actions.${image.id}'),
      );
      await tester.ensureVisible(menu);
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.getSize(menu).height, greaterThanOrEqualTo(44));
      await tester.tap(menu);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('smart-document.image-caption')),
        '协作图片说明😀',
      );
      await tester.enterText(
        find.byKey(const ValueKey('smart-document.image-alt')),
        '蓝色合成图片',
      );
      await tester.enterText(
        find.byKey(const ValueKey('smart-document.image-width')),
        '128',
      );
      await tester.tap(
        find.byKey(const ValueKey('smart-document.image-apply')),
      );
      await until(
        () => find
            .byKey(const ValueKey('smart-document.image-dialog'))
            .evaluate()
            .isEmpty,
      );
      expect(c.resolveBlock(ref)!.attributes['title'], '协作图片说明😀');
      await until(decodedImage);
      expect(tester.getSize(find.byType(RawImage)).width, 128.0);
      await c.synchronize();
      await bob.synchronize();
      // Independent property registers: peer size cannot erase author caption.
      c.pauseCollaboration(true);
      bob.pauseCollaboration(true);
      await c.updateImage(ref, {'title': '最终图片说明😀'});
      await bob.updateImage(ref, {
        'width': 160.0,
        'height': 160.0,
        'align': 'left',
      });
      c.pauseCollaboration(false);
      bob.pauseCollaboration(false);
      for (var i = 0; i < 8; i++) {
        await c.synchronize();
        await bob.synchronize();
      }
      expect(c.snapshot['data'], bob.snapshot['data']);
      expect(c.resolveBlock(ref)!.attributes['title'], '最终图片说明😀');
      expect(c.resolveBlock(ref)!.attributes['width'], 160.0);
      await tester.pump();
      expect(tester.getSize(find.byType(RawImage)).width, 160.0);
      checks.add(
        'image-metadata-and-peer-resize-change-actual-rendered-dimensions',
      );
      checks.add(
        'real-cloud-concurrent-image-caption-and-size-converge-as-independent-properties',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(menu);
      await tester.pump();
      await tester.tap(menu);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('smart-document.image-delete')),
      );
      await until(() => c.resolveBlock(ref) == null);
      await c.history();
      await tester.pump(const Duration(milliseconds: 300));
      expect(c.resolveBlock(ref), isNotNull);
      await c.synchronize();
      await bob.synchronize();
      expect(await w.session.prepareToClose(), isTrue);
      checks.add(
        'actual-image-delete-ui-origin-undo-and-public-sdk-checkpoint',
      );
      await until(decodedImage);
      checks.add('decoded-original-image-frame-visible-after-delete-undo');
      final evidence = Directory('${w.directory.path}/evidence');
      await evidence.create(recursive: true);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('stage1.surface')),
      );
      final capture = await boundary.toImage(pixelRatio: 1);
      final screenshot = (await capture.toByteData(
        format: ui.ImageByteFormat.png,
      ))!;
      await File(
        '${evidence.path}/media-editor.png',
      ).writeAsBytes(screenshot.buffer.asUint8List());
      capture.dispose();
      await File('${evidence.path}/media-e2e.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'platform': mobile ? 'ios' : 'macos',
          'run': StageOneWorkbench.run,
          'objectId': c.objectId,
          'image': ref.toJson(),
          'asset': asset.toJson(),
          'text': c.blocks.first.delta!.toPlainText(),
          'checks': checks,
          'pickerMode':
              'injected synthetic file adapter; system picker not certified',
          'limits': [
            'full SiYuan parity remains open',
            'complete collaboration remains open',
          ],
        }),
      );
      await bob.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await w.close();
      debugPrint('SMARTDOC_MEDIA_EVIDENCE=${evidence.path}');
    },
  );
}
