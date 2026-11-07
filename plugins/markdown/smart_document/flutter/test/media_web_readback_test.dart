import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'real browser file chooser image is readable by a second user through native core',
    () async {
      final fixture =
          jsonDecode(await File('../.build/e2e-fixture.json').readAsString())
              as Map;
      final dir = await Directory.systemTemp.createTemp('browser-filepicker-');
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/doc.json')),
        objectId: fixture['objectId'] as String,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(fixture['origin'] as String),
          workspaceId: fixture['workspaceId'] as String,
          deviceId: 'native-filepicker-readback',
          accessToken: () async =>
              fixture['users']['bob']['accessToken'] as String,
        ),
        syncInterval: null,
        editable: false,
      );
      final image = c.blocks.singleWhere(
        (n) => n.type == 'image' && n.attributes['title'] == '真实文件选择器上传',
      );
      expect(image.attributes['alt'], '通过浏览器选取的合成图片');
      expect(image.attributes['width'], 96.0);
      expect(image.attributes['height'], 96.0);
      final asset = AssetReference.fromJson(
        (image.attributes['asset'] as Map).cast<String, dynamic>(),
      );
      final repository = CloudAssetRepository(
        origin: Uri.parse(fixture['origin'] as String),
        workspaceId: fixture['workspaceId'] as String,
        accessToken: () async =>
            fixture['users']['bob']['accessToken'] as String,
      );
      expect(
        await repository.read(asset),
        await File('test/fixtures/test-image.png').readAsBytes(),
      );
      repository.close();
      await File('../.build/phase6-web-filepicker-readback.json').writeAsString(
        jsonEncode({
          'status': 'passed-filepicker-slice',
          'objectId': c.objectId,
          'blockId': image.id,
          'checks': [
            'actual-browser-filechooser-image-reference-read-by-second-native-user',
            'exact-description-alt-and-96px-square-attributes',
            'private-image-bytes-identical-to-selected-synthetic-file',
          ],
          'limits': ['accepted full-sync exchange is not durable ACK'],
        }),
      );
      await c.close();
      await dir.delete(recursive: true);
    },
    // Requires the actual browser file-picker step against this exact fixture
    // object before running. Keep all assertions; this is not a unit seed.
    tags: const ['manual-browser-filepicker'],
  );
}
