import 'dart:convert';
import 'dart:io';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'native prepares or verifies the same object used by the browser',
    () async {
      final root = Directory.current.parent;
      final fixture =
          jsonDecode(
                await File(
                  '${root.path}/.build/e2e-fixture.json',
                ).readAsString(),
              )
              as Map;
      final verify = Platform.environment['SMARTDOC_CROSS_MODE'] == 'verify';
      final provider = AppFlowyCollaborationProvider(
        origin: Uri.parse(fixture['origin'] as String),
        workspaceId: fixture['workspaceId'] as String,
        deviceId: 'native-cross-${verify ? 'verify' : 'prepare'}',
        accessToken: () async =>
            fixture['users']['alice']['accessToken'] as String,
      );
      final id = fixture['objectId'] as String;
      final dir = await Directory.systemTemp.createTemp('muse-cross-platform-');
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/native.json')),
        objectId: id,
        provider: provider,
        createRemote: !verify,
        syncInterval: null,
      );
      if (!verify) {
        final transaction = c.editor.transaction
          ..insertText(c.blocks.first, 0, 'Native种子😀');
        await c.editor.apply(transaction);
        for (var i = 0; i < 4; i++) {
          await c.synchronize();
          expect(c.syncState, DocumentSyncState.accepted, reason: c.failure);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        await File(
          '${root.path}/.build/cross-platform-seed.json',
        ).writeAsString(
          jsonEncode({
            'objectId': id,
            'firstBlockId': c.blocks.first.id,
            'text': c.blocks.first.delta!.toPlainText(),
          }),
        );
      } else {
        final seed =
            jsonDecode(
                  await File(
                    '${root.path}/.build/cross-platform-seed.json',
                  ).readAsString(),
                )
                as Map;
        expect(c.blocks.first.id, seed['firstBlockId']);
        final text = c.blocks.first.delta!.toPlainText();
        expect(text, contains('Native种子😀'));
        expect(text, contains('Web甲'));
        expect(text, contains('Web乙'));
        expect(
          c.blocks.any((n) => n.delta?.toPlainText() == 'Web 新增块'),
          isTrue,
        );
        final runs = c.blocks.first.delta!.toJson();
        final table = c.blocks.firstWhere((n) => n.type == 'table');
        final tableText = table.children.first.children.first;
        expect(tableText.delta!.toPlainText(), contains('Web表格甲'));
        expect(tableText.delta!.toPlainText(), contains('Web表格乙'));
        expect(
          tableText.delta!.toJson().any(
            (r) => (r['attributes'] as Map?)?['italic'] == true,
          ),
          isTrue,
        );
        expect(
          runs.any(
            (r) =>
                (r['insert'] as String).contains('Web乙') &&
                (r['attributes'] as Map?)?['bold'] == true,
          ),
          isTrue,
        );
        expect(
          runs.any(
            (r) =>
                (r['attributes'] as Map?)?['href'] ==
                'https://example.com/browser-document',
          ),
          isTrue,
        );
        final image = c.blocks.singleWhere((n) => n.type == 'image');
        expect(image.attributes['title'], '浏览器私有图片😀');
        final assets = CloudAssetRepository(
          origin: Uri.parse(fixture['origin'] as String),
          workspaceId: fixture['workspaceId'] as String,
          accessToken: () async =>
              fixture['users']['alice']['accessToken'] as String,
        );
        final imageBytes = await assets.read(
          AssetReference.fromJson(
            (image.attributes['asset'] as Map).cast<String, dynamic>(),
          ),
        );
        expect(imageBytes.length, greaterThan(0));
        assets.close();
        await File(
          '${root.path}/.build/native-web-readback.json',
        ).writeAsString(
          jsonEncode({
            'status': 'passed',
            'checks': [
              'same-native-block-id-after-browser-edits',
              'native-reads-browser-concurrent-unicode-and-marks',
              'native-reads-browser-inserted-block',
              'native-reads-browser-table-cell-concurrent-unicode-and-marks',
              'native-reads-browser-relative-href-mark',
              'native-reads-browser-image-registers-and-authenticated-private-bytes',
            ],
            'platform': 'macos-native',
            'date': DateTime.now().toUtc().toIso8601String(),
          }),
        );
      }
      await c.close();
      await dir.delete(recursive: true);
    },
  );
}
