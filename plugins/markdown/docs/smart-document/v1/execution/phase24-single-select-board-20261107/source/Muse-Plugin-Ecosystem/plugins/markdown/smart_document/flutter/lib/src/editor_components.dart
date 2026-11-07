import 'dart:async';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'table_components.dart';
import 'media_session.dart';
import 'image_components.dart';
import 'embedded_resources.dart';

bool smartDocumentInTable(EditorState editor) =>
    editor.selection != null &&
    editor
            .getNodeAtPath(editor.selection!.start.path)
            ?.findParent((n) => n.type == 'table/cell') !=
        null;

List<CommandShortcutEvent> smartDocumentCommandShortcuts({
  VoidCallback? editLink,
}) => [
  if (editLink != null)
    CommandShortcutEvent(
      key: 'muse-edit-link',
      command: 'cmd+k,ctrl+k',
      getDescription: () => '插入或编辑超链接',
      handler: (_) {
        editLink();
        return KeyEventResult.handled;
      },
    ),
  CommandShortcutEvent(
    key: 'muse-table-line-break',
    command: 'enter, shift+enter',
    getDescription: () => '单元格内换行',
    handler: (editor) {
      if (!smartDocumentInTable(editor)) return KeyEventResult.ignored;
      final selection = editor.selection!;
      if (!selection.isSingle) return KeyEventResult.handled;
      final node = editor.getNodeAtPath(selection.start.path)!;
      final tx = editor.transaction;
      final start = selection.startIndex;
      if (!selection.isCollapsed)
        tx.deleteText(node, start, selection.endIndex - start);
      tx.insertText(node, start, '\n');
      tx.afterSelection = Selection.collapsed(
        Position(path: node.path, offset: start + 1),
      );
      unawaited(editor.apply(tx));
      return KeyEventResult.handled;
    },
  ),
  for (final backward in [true, false])
    CommandShortcutEvent(
      key: 'muse-table-boundary-${backward ? 'backspace' : 'delete'}',
      command: backward ? 'backspace, shift+backspace' : 'delete, shift+delete',
      getDescription: () => '保持单元格边界',
      handler: (editor) {
        if (!smartDocumentInTable(editor)) return KeyEventResult.ignored;
        final selection = editor.selection!;
        final node = editor.getNodeAtPath(selection.start.path)!;
        final end = editor.getNodeAtPath(selection.end.path);
        final sameCell =
            node.findParent((n) => n.type == 'table/cell')?.id ==
            end?.findParent((n) => n.type == 'table/cell')?.id;
        if (!sameCell ||
            (selection.isCollapsed &&
                selection.startIndex == (backward ? 0 : node.delta?.length)))
          return KeyEventResult.handled;
        return KeyEventResult.ignored;
      },
    ),
  ...standardCommandShortcutEvents,
];

/// Same registered components for desktop, web and mobile. Nested content must
/// remain visible after a type conversion; the upstream heading is leaf-only.
Map<String, BlockComponentBuilder> smartDocumentBlockBuilders(
  SmartDocumentController controller, {
  DocumentMediaSession? media,
}) => {
  ...standardBlockComponentBuilderMap,
  'image': documentImageBuilder(controller, media),
  for (final type in ['grid', 'board', 'calendar'])
    type: DocumentDatabaseBuilder(controller),
  'table': SmartTableBuilder(controller),
  'table/cell': SmartTableCellBuilder(controller.editor),
  'paragraph': ParagraphBlockComponentBuilder(
    configuration: standardBlockComponentConfiguration.copyWith(
      padding: (node) => node.parent?.type == 'table/cell'
          ? EdgeInsets.zero
          : standardBlockComponentConfiguration.padding(node),
    ),
  ),
  'heading': ParagraphBlockComponentBuilder(
    configuration: standardBlockComponentConfiguration.copyWith(
      textStyle: (node, {textSpan}) {
        final level = (node.attributes['level'] as int? ?? 1).clamp(1, 6);
        return TextStyle(
          fontSize: const [32.0, 28.0, 24.0, 20.0, 18.0, 16.0][level - 1],
          fontWeight: FontWeight.w600,
          height: 1.4,
        );
      },
    ),
  ),
  'code': ParagraphBlockComponentBuilder(
    configuration: standardBlockComponentConfiguration.copyWith(
      placeholderText: (_) => '代码',
      textStyle: (_, {textSpan}) =>
          const TextStyle(fontFamily: 'monospace', height: 1.5),
    ),
  ),
};

/// Block-prefix formatting enters the domain as one atomic text/type command.
/// Literal code disables Markdown interpretation, including newline splitting.
List<CharacterShortcutEvent> smartDocumentCharacterShortcuts(
  SmartDocumentController controller, {
  CharacterShortcutEvent? slash,
}) {
  bool literal(EditorState editor) =>
      editor.selection != null &&
      (editor.getNodeAtPath(editor.selection!.start.path)?.type == 'code' ||
          editor
                  .getNodeAtPath(editor.selection!.start.path)
                  ?.findParent((n) => n.type == 'table/cell') !=
              null);
  Future<bool> prefix(EditorState editor, {bool fence = false}) async {
    final selection = editor.selection;
    if (selection == null || !selection.isCollapsed || literal(editor))
      return false;
    final node = editor.getNodeAtPath(selection.start.path);
    final text = node?.delta?.toPlainText();
    if (node == null || text == null || selection.startIndex > text.length)
      return false;
    final symbol = text.substring(0, selection.startIndex);
    String? type;
    int? level;
    final attrs = <String, dynamic>{};
    if (fence) {
      final match = RegExp(r'^```([a-zA-Z0-9_+\-]*)$').firstMatch(symbol);
      if (match == null) return false;
      type = 'code';
      attrs['language'] = match[1]!.isEmpty ? 'plain text' : match[1]!;
    } else if (RegExp(r'^#{1,6}$').hasMatch(symbol)) {
      type = 'heading';
      level = symbol.length;
    } else if (RegExp(r'^[-*+]$').hasMatch(symbol)) {
      type = 'bulleted_list';
    } else if (symbol == '>') {
      type = 'quote';
    } else if (RegExp(r'^-?\[( |x|X)?\]$').hasMatch(symbol)) {
      type = 'todo_list';
      attrs['checked'] = symbol.toLowerCase().contains('x');
    } else {
      final match = RegExp(r'^(\d{1,6})\.$').firstMatch(symbol);
      if (match != null) {
        type = 'numbered_list';
        attrs['number'] = int.parse(match[1]!);
      }
    }
    if (type == null) return false;
    await controller.formatMarkdownPrefix(
      symbol,
      type,
      level: level,
      attributes: attrs,
    );
    return true;
  }

  CharacterShortcutEvent guarded(CharacterShortcutEvent event) =>
      CharacterShortcutEvent(
        key: event.key,
        character: event.character,
        regExp: event.regExp,
        handler: (editor) async =>
            literal(editor) ? false : await event.handler(editor),
        handlerWithCharacter: event.handlerWithCharacter == null
            ? null
            : (editor, char) async => literal(editor)
                  ? false
                  : await event.handlerWithCharacter!(editor, char),
      );
  return [
    CharacterShortcutEvent(
      key: 'muse-stable-markdown-prefix',
      character: ' ',
      handler: (editor) => prefix(editor),
    ),
    CharacterShortcutEvent(
      key: 'muse-stable-code-fence',
      character: '\n',
      handler: (editor) => prefix(editor, fence: true),
    ),
    for (final event in standardCharacterShortcutEvents)
      if (event.key != slashCommand.key) guarded(event),
    if (slash != null) guarded(slash),
  ];
}
