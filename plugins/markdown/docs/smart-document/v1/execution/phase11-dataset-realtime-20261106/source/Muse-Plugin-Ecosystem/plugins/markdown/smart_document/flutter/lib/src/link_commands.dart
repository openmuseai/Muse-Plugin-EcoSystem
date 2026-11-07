import 'package:appflowy_editor/appflowy_editor.dart';
import 'controller.dart';
import 'core_api.dart';

/// Opaque Yrs positions, scoped to a stable document/text identity. Domain-only:
/// no widget context, network credential or transient editor path is persisted.
final class DocumentTextRange {
  DocumentTextRange._(Map<String, dynamic> value)
    : value = Map.unmodifiable(value);
  final Map<String, dynamic> value;
  String get text => value['text'] as String;
  String get blockId => value['blockId'] as String;
  String get objectId => value['objectId'] as String;
  Map<String, dynamic> toJson() => Map.of(value);
}

extension SmartDocumentLinkCommands on SmartDocumentController {
  DocumentTextRange? captureTextRange([Selection? selected]) {
    final selection = selected ?? editor.selection;
    if (selection == null || !selection.isSingle) return null;
    final node = editor.getNodeAtPath(selection.start.path);
    if (node?.delta == null) return null;
    return DocumentTextRange._(
      core.call({
        'action': 'captureTextRange',
        'handle': handle,
        'blockId': node!.id,
        'start': selection.startIndex,
        'end': selection.endIndex,
      }),
    );
  }

  String? linkAtRange(DocumentTextRange range) {
    final node = resolveBlock(
      DocumentBlockReference(objectId: range.objectId, blockId: range.blockId),
    );
    if (node == null) throw const SmartDocumentFailure('TARGET_MISSING');
    final resolved = core.call({
      'action': 'resolveTextRange',
      'handle': handle,
      'anchor': range.toJson(),
    });
    var cursor = 0;
    final offset = resolved['start'] as int;
    for (final run in node.delta!.toJson()) {
      final text = run['insert'] as String;
      if (cursor <= offset && offset < cursor + text.length)
        return (run['attributes'] as Map?)?['href'] as String?;
      cursor += text.length;
    }
    return null;
  }

  Future<void> applyLink(
    DocumentTextRange range, {
    required String? href,
    String? label,
  }) => executeDomainOperations([
    {
      'op': 'apply_link',
      'anchor': range.toJson(),
      'href': href,
      if (label != null) 'label': label,
    },
  ]);
}
