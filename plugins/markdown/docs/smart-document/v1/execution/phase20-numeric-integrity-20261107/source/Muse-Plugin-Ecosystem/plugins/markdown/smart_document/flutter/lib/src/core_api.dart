import 'package:muse_collab_contract/muse_collab_contract.dart';

const smartDocumentCollaborationBinding = CollaborationBinding(
  protocol: 'appflowy.full-sync/1',
  engine: 'appflowy-collab/e59260e524f33104b0ddcd6bb8f6218cad0f7e18',
  encoding: 'yrs.update-v1',
  schema: 'appflowy.document/0.2',
  epoch: 0,
);

final class SmartDocumentFailure implements Exception {
  const SmartDocumentFailure(this.code);
  final String code;
  @override
  String toString() => 'SmartDocumentFailure($code)';
}

/// No UI, file paths or network authority is passed across the domain boundary.
abstract interface class DocumentCore {
  Map<String, dynamic> call(Map<String, dynamic> request);
}

/// A block address, scoped to its document object. It grants no access and
/// deliberately contains no transient tree path or absolute text offset.
final class DocumentBlockReference {
  const DocumentBlockReference({required this.objectId, required this.blockId});
  final String objectId;
  final String blockId;
  Map<String, dynamic> toJson() => {'objectId': objectId, 'blockId': blockId};
  factory DocumentBlockReference.fromJson(Map<String, dynamic> value) {
    final object = value['objectId'], block = value['blockId'];
    if (object is! String ||
        object.isEmpty ||
        block is! String ||
        block.isEmpty ||
        block.length > 256) {
      throw const SmartDocumentFailure('INVALID_BLOCK_REFERENCE');
    }
    return DocumentBlockReference(objectId: object, blockId: block);
  }
  @override
  bool operator ==(Object other) =>
      other is DocumentBlockReference &&
      other.objectId == objectId &&
      other.blockId == blockId;
  @override
  int get hashCode => Object.hash(objectId, blockId);
}
