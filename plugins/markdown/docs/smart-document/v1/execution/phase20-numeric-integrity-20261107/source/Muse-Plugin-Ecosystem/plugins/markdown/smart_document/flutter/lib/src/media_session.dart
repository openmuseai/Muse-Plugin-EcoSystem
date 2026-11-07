import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:mime/mime.dart';
import 'package:image/image.dart' as image_metadata;
import 'package:crypto/crypto.dart';
import 'asset_repository.dart';
import 'controller.dart';
import 'core_api.dart';
import 'image_commands.dart';
import 'store_api.dart';

final class PickedDocumentImage {
  const PickedDocumentImage(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

typedef DocumentImagePicker = Future<PickedDocumentImage?> Function();
Future<PickedDocumentImage?> pickDocumentImage() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
    withData: true,
  );
  if (result == null) return null;
  final file = result.files.single;
  if (file.bytes == null) throw const AssetFailure('IMAGE_BYTES_UNAVAILABLE');
  return PickedDocumentImage(file.bytes!, file.name);
}

/// Application workflow: durable upload draft -> repository receipt -> one CRDT
/// insertion -> draft cleanup. Domain state never contains bytes or credentials.
/// Explicit retries use the same block ID; the core receipt survives undo.
final class DocumentMediaSession extends ChangeNotifier {
  DocumentMediaSession({
    required this.controller,
    required this.repository,
    required this.draftStore,
    DocumentImagePicker? picker,
  }) : picker = picker ?? pickDocumentImage;
  final SmartDocumentController controller;
  final AssetRepository repository;
  final DocumentStore draftStore;
  final DocumentImagePicker picker;
  Map<String, dynamic>? _draft;
  bool busy = false;
  Object? error;
  bool get hasPending => _draft != null;
  String get draftName => _draft?['name'] as String? ?? '图片';
  Future<void> restore() async {
    final record = await draftStore.read();
    final draft = record?['draft'];
    if (draft is Map) {
      if (draft['objectId'] != controller.objectId)
        throw const AssetFailure('DRAFT_SCOPE_MISMATCH');
      _draft = draft.cast<String, dynamic>();
    }
    notifyListeners();
  }

  Future<void> insert({DocumentBlockReference? after}) async {
    if (busy || hasPending) throw const AssetFailure('UPLOAD_ALREADY_PENDING');
    if (!controller.canWrite || !controller.editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    busy = true;
    error = null;
    notifyListeners();
    try {
      final picked = await picker();
      if (picked == null) return;
      if (picked.bytes.isEmpty || picked.bytes.length > 12 * 1024 * 1024)
        throw const AssetFailure('ASSET_TOO_LARGE');
      final type = lookupMimeType(picked.name, headerBytes: picked.bytes);
      // Filename alone is not proof: the platform decoder also verifies bytes.
      if (!{
        'image/png',
        'image/jpeg',
        'image/gif',
        'image/webp',
      }.contains(type))
        throw const AssetFailure('UNSUPPORTED_IMAGE_TYPE');
      // Existing image package parses headers before a platform decoder can
      // allocate pixels. ImageDescriptor.width is unsupported on Flutter Web.
      final metadata = image_metadata
          .findDecoderForData(picked.bytes)
          ?.startDecode(picked.bytes);
      void checkSize(int w, int h) {
        if (w < 1 || h < 1 || w > 20000 || h > 20000 || w * h > 40000000)
          throw const AssetFailure('IMAGE_PIXEL_LIMIT');
      }

      if (metadata == null) throw const AssetFailure('INVALID_IMAGE_BYTES');
      checkSize(metadata.width, metadata.height);
      var intrinsicWidth = metadata.width, intrinsicHeight = metadata.height;
      final buffer = await ui.ImmutableBuffer.fromUint8List(picked.bytes);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (w, h) {
          checkSize(w, h);
          intrinsicWidth = w;
          intrinsicHeight = h;
          return const ui.TargetImageSize(width: 1, height: 1);
        },
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      final width = math.min(intrinsicWidth.toDouble(), 640.0);
      _draft = {
        'objectId': controller.objectId,
        'blockId':
            'image-${sha256.convert(utf8.encode('${controller.objectId}:${DateTime.now().microsecondsSinceEpoch}:${picked.bytes.length}'))}',
        'name': picked.name.substring(0, math.min(picked.name.length, 256)),
        'bytes': base64Encode(picked.bytes),
        'mediaType': type,
        'width': width,
        'height': width * intrinsicHeight / intrinsicWidth,
        if (after != null) 'after': after.toJson(),
      };
      await _save();
      await _commit();
    } on Object catch (e) {
      error = e;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> retry() async {
    if (busy || _draft == null) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _save();
      await _commit();
    } on Object catch (e) {
      error = e;
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _save() => draftStore.write({'draft': _draft});
  Future<void> _commit() async {
    if (!controller.canWrite || !controller.editor.editable) {
      throw const SmartDocumentFailure('READ_ONLY');
    }
    final draft = _draft!;
    final bytes = base64Decode(draft['bytes'] as String);
    final ref = draft['asset'] is Map
        ? AssetReference.fromJson(
            (draft['asset'] as Map).cast<String, dynamic>(),
          )
        : await repository.put(
            owner: controller.objectId,
            bytes: bytes,
            mediaType: draft['mediaType'] as String,
          );
    draft['asset'] = ref.toJson();
    await _save();
    await controller.insertImage(
      blockId: draft['blockId'] as String,
      asset: ref,
      width: (draft['width'] as num).toDouble(),
      height: (draft['height'] as num).toDouble(),
      after: draft['after'] is Map
          ? DocumentBlockReference.fromJson(
              (draft['after'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
    await draftStore.write({'draft': null});
    _draft = null;
  }

  Future<void> cancel() async {
    if (busy) return;
    await draftStore.write({'draft': null});
    _draft = null;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    repository.close();
    super.dispose();
  }
}
