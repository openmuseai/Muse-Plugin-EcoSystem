import 'controller.dart';
import 'core_api.dart';
import 'asset_repository.dart';

extension SmartDocumentImageCommands on SmartDocumentController {
  Future<void> insertImage({
    required String blockId,
    required AssetReference asset,
    required double width,
    required double height,
    DocumentBlockReference? after,
  }) {
    if (after != null && after.objectId != objectId)
      throw const SmartDocumentFailure('FOREIGN_BLOCK_REFERENCE');
    return executeDomainOperations([
      {
        'op': 'insert_image',
        if (after != null) 'afterBlockId': after.blockId,
        'node': {
          'id': blockId,
          'type': 'image',
          'data': {
            'asset': asset.toJson(),
            'url': 'muse-asset://${asset.owner}/${asset.sha256}',
            'width': width,
            'height': height,
            'align': 'center',
            'alt': '',
            'title': '',
          },
        },
      },
    ]);
  }

  Future<void> updateImage(
    DocumentBlockReference reference,
    Map<String, dynamic> properties,
  ) {
    if (reference.objectId != objectId)
      throw const SmartDocumentFailure('FOREIGN_BLOCK_REFERENCE');
    return executeDomainOperations([
      {
        'op': 'update_image',
        'blockId': reference.blockId,
        'attributes': properties,
      },
    ]);
  }

  Future<void> deleteImage(DocumentBlockReference reference) async {
    final node = resolveBlock(reference);
    if (node == null || node.type != 'image')
      throw const SmartDocumentFailure('TARGET_MISSING');
    if (!canWrite || !editor.editable)
      throw const SmartDocumentFailure('READ_ONLY');
    await editor.apply(editor.transaction..deleteNode(node));
    await flush();
  }
}
