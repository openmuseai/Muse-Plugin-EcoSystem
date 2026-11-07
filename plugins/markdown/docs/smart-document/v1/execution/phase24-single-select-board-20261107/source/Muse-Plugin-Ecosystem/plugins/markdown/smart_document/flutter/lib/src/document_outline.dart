import 'package:flutter/foundation.dart';
import 'core_api.dart';

/// Content query DTO. No widget, transport, local collapse state or tree paths.
@immutable
final class DocumentOutlineEntry {
  const DocumentOutlineEntry({
    required this.reference,
    required this.level,
    required this.depth,
    required this.parentId,
    required this.text,
    required this.truncated,
  });
  final DocumentBlockReference reference;
  final int level, depth;
  final String? parentId;
  final String text;
  final bool truncated;
  String get label => text.trim().isEmpty ? '未命名标题' : text;
}

@immutable
final class DocumentOutline {
  const DocumentOutline({
    required this.ready,
    required this.entries,
    this.warnings = 0,
  });
  final bool ready;
  final List<DocumentOutlineEntry> entries;
  final int warnings;
  static const unavailable = DocumentOutline(ready: false, entries: []);
  static DocumentOutline decode(String objectId, dynamic value) {
    if (value is! Map ||
        value['profile'] != 'muse.document.outline/1' ||
        value['ready'] != true)
      return unavailable;
    final raw = value['entries'];
    if (raw is! List || raw.length > 10000) return unavailable;
    final entries = <DocumentOutlineEntry>[];
    final stack = <DocumentOutlineEntry>[];
    final ids = <String>{};
    for (final item in raw) {
      if (item is! Map) return unavailable;
      final id = item['blockId'],
          level = item['level'],
          depth = item['depth'],
          text = item['text'];
      if (id is! String ||
          id.isEmpty ||
          id.length > 256 ||
          !ids.add(id) ||
          level is! int ||
          level < 1 ||
          level > 6 ||
          depth is! int ||
          text is! String ||
          text.runes.length > 256 ||
          item['truncated'] is! bool)
        return unavailable;
      while (stack.isNotEmpty && stack.last.level >= level) {
        stack.removeLast();
      }
      if (depth != stack.length ||
          item['parentId'] !=
              (stack.isEmpty ? null : stack.last.reference.blockId))
        return unavailable;
      final entry = DocumentOutlineEntry(
        reference: DocumentBlockReference(objectId: objectId, blockId: id),
        level: level,
        depth: depth,
        parentId: item['parentId'] as String?,
        text: text,
        truncated: item['truncated'] as bool,
      );
      entries.add(entry);
      stack.add(entry);
    }
    return DocumentOutline(
      ready: true,
      entries: List.unmodifiable(entries),
      warnings: value['warnings'] is int ? value['warnings'] as int : 0,
    );
  }
}
