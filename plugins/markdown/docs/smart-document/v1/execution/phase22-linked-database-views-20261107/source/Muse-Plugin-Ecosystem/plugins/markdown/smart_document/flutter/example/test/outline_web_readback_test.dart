import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class _Memory implements DocumentStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> read() async => value;
  @override
  Future<void> write(Map<String, dynamic> v) async {
    value = v;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'native reads exact browser title restoration from the same original Cloud object',
    () async {
      final root = Directory('../../.build');
      final config =
          jsonDecode(
                await File(
                  '${root.path}/outline-web-public.json',
                ).readAsString(),
              )
              as Map;
      final f =
          jsonDecode(await File('${root.path}/e2e-fixture.json').readAsString())
              as Map;
      final receipt =
          jsonDecode(
                await File(
                  '${root.path}/outline-web-result.json',
                ).readAsString(),
              )
              as Map;
      expect(receipt['objectId'], config['OUTLINE_OBJECT']);
      expect(receipt['checks'], hasLength(8));
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: _Memory(),
        objectId: config['OUTLINE_OBJECT'] as String,
        editable: false,
        syncInterval: null,
        provider: AppFlowyCollaborationProvider(
          origin: Uri.parse(config['SMARTDOC_ORIGIN'] as String),
          workspaceId: config['SMARTDOC_WORKSPACE'] as String,
          deviceId: 'outline-native-readback',
          accessToken: () async => f['users']['bob']['accessToken'] as String,
        ),
      );
      expect(c.snapshot['outline'], receipt['outline']);
      expect(
        c.outline.entries
            .singleWhere(
              (e) => e.reference.blockId == config['OUTLINE_HEADING'],
            )
            .text,
        'Web 重连 远端 协作章节😀',
      );
      expect(c.canWrite, isFalse);
      expect(jsonEncode(await c.store.read()), isNot(contains('accessToken')));
      await File('${root.path}/outline-native-web-readback.json').writeAsString(
        jsonEncode({
          'status': 'passed',
          'objectId': c.objectId,
          'checks': [
            'same-native-ios-browser-cloud-object',
            'identical-derived-outline-in-fresh-rust-kernel',
            'peer-restored-heading-identity-and-unicode-title',
            'readonly-readback-and-no-credential-in-content',
          ],
        }),
      );
      await c.close();
    },
    timeout: const Timeout(Duration(seconds: 120)),
  );
}
