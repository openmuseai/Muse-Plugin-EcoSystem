import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'core_api.dart';

/// Fixed-grid editing surface. Cell height/width are a local layout result;
/// neither rendering nor resizing the viewport emits a document transaction.
final class SmartTableBuilder extends BlockComponentBuilder {
  SmartTableBuilder(this.controller);
  final SmartDocumentController controller;
  @override
  BlockComponentValidate get validate =>
      (n) => n.attributes['museTable'] == 'fixed-grid/1';
  @override
  BlockComponentWidget build(BlockComponentContext context) => _TableSurface(
    key: context.node.key,
    node: context.node,
    controller: controller,
    configuration: configuration,
  );
}

final class SmartTableCellBuilder extends BlockComponentBuilder {
  SmartTableCellBuilder(this.editor);
  final EditorState editor;
  @override
  BlockComponentValidate get validate =>
      (n) => n.children.isNotEmpty;
  @override
  BlockComponentWidget build(BlockComponentContext context) => _CellSurface(
    key: context.node.key,
    node: context.node,
    editor: editor,
    configuration: configuration,
  );
}

class _CellSurface extends BlockComponentStatelessWidget {
  const _CellSurface({
    super.key,
    required super.node,
    required super.configuration,
    required this.editor,
  });
  final EditorState editor;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 44),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final child in node.children)
            editor.renderer.build(context, child),
        ],
      ),
    ),
  );
}

class _TableSurface extends BlockComponentStatefulWidget {
  const _TableSurface({
    super.key,
    required super.node,
    required super.configuration,
    required this.controller,
  });
  final SmartDocumentController controller;
  @override
  State<_TableSurface> createState() => _TableSurfaceState();
}

class _TableSurfaceState extends State<_TableSurface> with SelectableMixin {
  final _scroll = ScrollController();
  Node get node => widget.node;
  SmartDocumentController get c => widget.controller;
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rows = node.attributes['rowsLen'] as int;
    final cols = node.attributes['colsLen'] as int;
    final cells = {
      for (final cell in node.children)
        '${cell.attributes['rowPosition']}:${cell.attributes['colPosition']}':
            cell,
    };
    final color = Theme.of(context).colorScheme.outlineVariant;
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (c.canWrite && c.editor.editable)
            SizedBox(
              height: 44,
              child: PopupMenuButton<String>(
                key: ValueKey('smart-document.table-menu.${node.id}'),
                tooltip: '表格操作',
                requestFocus: false,
                icon: const Icon(Icons.more_horiz, size: 18),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'delete', child: Text('删除表格')),
                ],
                onSelected: (_) async {
                  try {
                    await c.deleteTable(
                      DocumentBlockReference(
                        objectId: c.objectId,
                        blockId: node.id,
                      ),
                    );
                  } on Object {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('表格操作未完成，请重试')),
                      );
                  }
                },
              ),
            ),
          Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: cols * 160.0,
                child: Table(
                  defaultColumnWidth: const FixedColumnWidth(160),
                  defaultVerticalAlignment: TableCellVerticalAlignment.top,
                  border: TableBorder.all(color: color),
                  children: [
                    for (var row = 0; row < rows; row++)
                      TableRow(
                        children: [
                          for (var col = 0; col < cols; col++)
                            c.editor.renderer.build(
                              context,
                              cells['$row:$col']!,
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: c.editor.selectionNotifier,
      remoteSelection: c.editor.remoteSelections,
      blockColor: c.editor.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );
  }

  RenderBox? get box => context.findRenderObject() as RenderBox?;
  @override
  Position start() => Position(path: node.path);
  @override
  Position end() => Position(path: node.path, offset: 1);
  @override
  Position getPositionInOffset(Offset offset) => end();
  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: node.path, startOffset: 0, endOffset: 1);
  @override
  bool get shouldCursorBlink => false;
  @override
  CursorStyle get cursorStyle => CursorStyle.cover;
  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) =>
      Offset.zero & (box?.size ?? Size.zero);
  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) => [getBlockRect(shiftWithBaseOffset: shiftWithBaseOffset)];
  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) => getBlockRect();
  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      box?.localToGlobal(offset) ?? offset;
}
