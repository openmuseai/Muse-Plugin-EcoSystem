import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image_fixture;
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

class Repository implements AssetRepository {
  bool fail = false;
  int puts = 0;
  @override
  Future<AssetReference> put({
    required String owner,
    required Uint8List bytes,
    required String mediaType,
  }) async {
    puts++;
    if (fail) throw const AssetFailure('UNAVAILABLE');
    final hash = sha256.convert(bytes).toString();
    return AssetReference(
      provider: 'muse.local-assets/1',
      scope: 'private-test',
      owner: owner,
      key: hash,
      mediaType: mediaType,
      byteLength: bytes.length,
      sha256: hash,
    );
  }

  @override
  Future<Uint8List> read(AssetReference ref) async =>
      File('test/fixtures/test-image.png').readAsBytes();
  @override
  void close() {}
}

class CleanupFailureStore implements DocumentStore {
  CleanupFailureStore(this.source);
  final DocumentStore source;
  bool failCleanup = true;
  @override
  Future<Map<String, dynamic>?> read() => source.read();
  @override
  Future<void> write(Map<String, dynamic> record) async {
    if (record['draft'] == null && failCleanup)
      throw StateError('synthetic cleanup failure');
    await source.write(record);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'durable failed upload restores and retries same image once; metadata and deletion undo reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('smart-image-');
      final store = FileDocumentStore(File('${dir.path}/document.json'));
      const object = '041c01d0-831a-408a-b8fa-190d40dd9e95';
      var c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: object,
      );
      final draft = FileDocumentStore(File('${dir.path}/draft.json'));
      final repository = Repository()..fail = true;
      var media = DocumentMediaSession(
        controller: c,
        repository: repository,
        draftStore: draft,
        picker: () async => PickedDocumentImage(
          await File('test/fixtures/test-image.png').readAsBytes(),
          'test-image.png',
        ),
      );
      await expectLater(media.insert(), throwsA(isA<AssetFailure>()));
      expect(media.hasPending, isTrue);
      expect(c.blocks.where((b) => b.type == 'image'), isEmpty);
      media.dispose();
      await c.close();
      c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: object,
      );
      repository.fail = false;
      media = DocumentMediaSession(
        controller: c,
        repository: repository,
        draftStore: draft,
      );
      await media.restore();
      expect(media.hasPending, isTrue);
      c.editor.editable = false;
      await expectLater(media.retry(), throwsA(isA<SmartDocumentFailure>()));
      expect(repository.puts, 1);
      c.editor.editable = true;
      await media.retry();
      expect(media.hasPending, isFalse);
      final node = c.blocks.singleWhere((b) => b.type == 'image');
      final ref = DocumentBlockReference(objectId: object, blockId: node.id);
      await c.updateImage(ref, {
        'title': '图片说明😀',
        'alt': '合成测试图片',
        'width': 128.0,
        'height': 128.0,
      });
      expect(c.resolveBlock(ref)!.attributes['title'], '图片说明😀');
      await c.deleteImage(ref);
      expect(c.resolveBlock(ref), isNull);
      await c.history();
      expect(c.resolveBlock(ref), isNotNull);
      await c.close();
      media.dispose();
      c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: store,
        objectId: object,
      );
      expect(c.resolveBlock(ref)!.attributes['title'], '图片说明😀');
      expect(c.failure, isNull);
      await c.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'failed draft cleanup retry cannot resurrect a user-undone image or upload twice',
    () async {
      final dir = await Directory.systemTemp.createTemp('smart-image-replay-');
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/doc.json')),
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e96',
      );
      final draft = CleanupFailureStore(
        FileDocumentStore(File('${dir.path}/draft.json')),
      );
      final repository = Repository();
      final media = DocumentMediaSession(
        controller: c,
        repository: repository,
        draftStore: draft,
        picker: () async => PickedDocumentImage(
          await File('test/fixtures/test-image.png').readAsBytes(),
          'test.png',
        ),
      );
      await expectLater(media.insert(), throwsStateError);
      expect(media.hasPending, isTrue);
      expect(repository.puts, 1);
      expect(c.blocks.where((n) => n.type == 'image'), hasLength(1));
      await c.history();
      expect(c.blocks.where((n) => n.type == 'image'), isEmpty);
      draft.failCleanup = false;
      await media.retry();
      expect(media.hasPending, isFalse);
      expect(repository.puts, 1);
      expect(c.blocks.where((n) => n.type == 'image'), isEmpty);
      await c.close();
      media.dispose();
      await dir.delete(recursive: true);
    },
  );
  test(
    'corrupt and oversized image headers never create a draft, upload or document block',
    () async {
      final dir = await Directory.systemTemp.createTemp('smart-image-limits-');
      final c = await SmartDocumentController.open(
        core: NativeDocumentCore(),
        store: FileDocumentStore(File('${dir.path}/doc.json')),
        objectId: '041c01d0-831a-408a-b8fa-190d40dd9e97',
      );
      for (final bytes in [
        Uint8List.fromList([1, 2, 3]),
        image_fixture.encodePng(image_fixture.Image(width: 20001, height: 1)),
      ]) {
        final repository = Repository();
        final media = DocumentMediaSession(
          controller: c,
          repository: repository,
          draftStore: FileDocumentStore(File('${dir.path}/draft.json')),
          picker: () async => PickedDocumentImage(bytes, 'fake.png'),
        );
        await expectLater(media.insert(), throwsA(isA<Object>()));
        expect(media.hasPending, isFalse);
        expect(repository.puts, 0);
        expect(c.blocks.where((n) => n.type == 'image'), isEmpty);
        media.dispose();
      }
      await c.close();
      await dir.delete(recursive: true);
    },
  );
}
