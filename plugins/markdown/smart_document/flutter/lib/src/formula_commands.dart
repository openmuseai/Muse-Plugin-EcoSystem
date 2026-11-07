import 'package:uuid/uuid.dart';
import 'controller.dart';
import 'core_api.dart';

/// Immutable edit draft scoped to an original formula block. Hash is a local
/// precondition, not a distributed compare-and-swap or a collaboration protocol.
final class DocumentFormulaDraft {
  const DocumentFormulaDraft({
    required this.reference,
    required this.formula,
    required this.hash,
  });
  final DocumentBlockReference reference;
  final String formula, hash;
}

extension SmartDocumentFormulaCommands on SmartDocumentController {
  DocumentFormulaDraft captureFormula(DocumentBlockReference reference) {
    if (reference.objectId != objectId)
      throw const SmartDocumentFailure('FOREIGN_BLOCK_REFERENCE');
    final value = core.call({
      'action': 'formulaState',
      'handle': handle,
      'blockId': reference.blockId,
    });
    return DocumentFormulaDraft(
      reference: reference,
      formula: value['formula'] as String,
      hash: value['hash'] as String,
    );
  }

  Future<DocumentBlockReference> insertFormula(
    String formula, {
    DocumentBlockReference? after,
    String? blockId,
  }) async {
    if (after != null && after.objectId != objectId)
      throw const SmartDocumentFailure('FOREIGN_BLOCK_REFERENCE');
    final id = blockId ?? const Uuid().v4();
    await executeDomainOperations([
      {
        'op': 'insert_formula',
        'blockId': id,
        'formula': formula,
        if (after != null) 'afterBlockId': after.blockId,
      },
    ]);
    return DocumentBlockReference(objectId: objectId, blockId: id);
  }

  Future<void> updateFormula(DocumentFormulaDraft draft, String formula) =>
      _formulaCommand(draft, {'op': 'update_formula', 'formula': formula});
  Future<void> deleteFormula(DocumentFormulaDraft draft) =>
      _formulaCommand(draft, {'op': 'delete_formula'});
  Future<void> _formulaCommand(
    DocumentFormulaDraft draft,
    Map<String, dynamic> command,
  ) {
    if (draft.reference.objectId != objectId)
      throw const SmartDocumentFailure('FOREIGN_BLOCK_REFERENCE');
    return executeDomainOperations([
      {
        ...command,
        'blockId': draft.reference.blockId,
        'expectedHash': draft.hash,
      },
    ]);
  }
}
