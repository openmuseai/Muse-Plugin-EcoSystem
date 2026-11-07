import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'core_api.dart';
import 'document_outline.dart';

/// Local surface state. The content kernel owns the outline query and the
/// original editor owns scrolling. Collapse and navigation never write CRDT.
final class DocumentOutlineCoordinator extends ChangeNotifier {
  DocumentOutlineCoordinator(this.document)
    : scroll = EditorScrollController(editorState: document.editor) {
    document.addListener(_contentChanged);
    scroll.itemPositionsListener.itemPositions.addListener(_scrollChanged);
  }
  final SmartDocumentController document;
  final viewportKey = GlobalKey();
  final EditorScrollController scroll;
  final Set<String> _collapsed = {};
  String? activeId;
  bool _disposed = false, _scheduled = false;
  int _navigationEpoch = 0;
  DocumentOutline get outline => document.outline;
  bool collapsed(String id) => _collapsed.contains(id);
  List<DocumentOutlineEntry> get visibleEntries {
    final hidden = <String>{};
    return outline.entries
        .where((entry) {
          final hiddenByParent = hidden.contains(entry.parentId);
          if (hiddenByParent || collapsed(entry.reference.blockId))
            hidden.add(entry.reference.blockId);
          return !hiddenByParent;
        })
        .toList(growable: false);
  }

  void toggle(String id) {
    if (_disposed || !outline.entries.any((e) => e.reference.blockId == id))
      return;
    if (!_collapsed.remove(id)) _collapsed.add(id);
    notifyListeners();
  }

  void _contentChanged() {
    if (_disposed) return;
    final ids = outline.entries.map((e) => e.reference.blockId).toSet();
    _collapsed.removeWhere((id) => !ids.contains(id));
    if (!ids.contains(activeId)) activeId = null;
    _scrollChanged();
    notifyListeners();
  }

  void _scrollChanged() {
    if (_disposed || _scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || document.isClosed || !document.canRead) return;
      final positions =
          scroll.itemPositionsListener.itemPositions.value
              .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
      final header = document.editor.showHeader ? 1 : 0;
      final first = positions
          .where(
            (p) =>
                p.index >= header && p.index - header < document.blocks.length,
          )
          .firstOrNull;
      if (first == null) return;
      final rootIndex = first.index - header;
      String? current;
      for (final entry in outline.entries) {
        final node = document.resolveBlock(entry.reference);
        if (node == null || node.path.isEmpty) continue;
        if (node.path.first <= rootIndex)
          current = entry.reference.blockId;
        else
          break;
      }
      if (current != activeId) {
        activeId = current;
        notifyListeners();
      }
    });
  }

  Future<bool> navigate(DocumentBlockReference reference) async {
    final epoch = ++_navigationEpoch;
    bool alive() =>
        !_disposed &&
        !document.isClosed &&
        document.canRead &&
        epoch == _navigationEpoch;
    if (!alive() || reference.objectId != document.objectId) return false;
    await document.projectionReady;
    if (!alive() || !outline.entries.any((e) => e.reference == reference))
      return false;
    final node = document.resolveBlock(reference);
    if (node == null ||
        node.path.isEmpty ||
        !scroll.itemScrollController.isAttached)
      return false;
    scroll.itemScrollController.jumpTo(
      index: node.path.first + (document.editor.showHeader ? 1 : 0),
    );
    await WidgetsBinding.instance.endOfFrame;
    if (!alive() || !outline.entries.any((e) => e.reference == reference))
      return false;
    final fresh = document.resolveBlock(reference);
    final context = fresh?.key.currentContext;
    if (fresh == null || context == null) return false;
    if (fresh.path.length > 1) {
      final box = context.findRenderObject();
      final viewport = viewportKey.currentContext?.findRenderObject();
      if (box is! RenderBox ||
          viewport is! RenderBox ||
          !box.hasSize ||
          !viewport.hasSize)
        return false;
      final delta =
          box.localToGlobal(Offset.zero).dy -
          viewport.localToGlobal(Offset.zero).dy;
      await scroll.scrollOffsetController.animateTo(
        offset: delta,
        duration: const Duration(milliseconds: 1),
      );
    }
    if (!alive()) return false;
    activeId = reference.blockId;
    notifyListeners();
    return true;
  }

  void deactivate() {
    if (_disposed) return;
    _disposed = true;
    _navigationEpoch++;
    document.removeListener(_contentChanged);
    scroll.itemPositionsListener.itemPositions.removeListener(_scrollChanged);
  }

  @override
  void dispose() {
    deactivate();
    scroll.dispose();
    super.dispose();
  }
}

final class DocumentOutlineView extends StatelessWidget {
  const DocumentOutlineView({
    super.key,
    required this.coordinator,
    this.onNavigate,
    this.scrollable = true,
  });
  final DocumentOutlineCoordinator coordinator;
  final Future<void> Function(DocumentBlockReference)? onNavigate;
  final bool scrollable;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: coordinator,
    builder: (context, _) {
      final outline = coordinator.outline;
      if (!coordinator.document.canRead || coordinator.document.isClosed)
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('目录暂不可用'),
        );
      if (!outline.ready)
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('当前文档目录暂不可用'),
        );
      if (outline.entries.isEmpty)
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('添加标题后，将在这里显示目录'),
        );
      final entries = coordinator.visibleEntries;
      final parents = outline.entries
          .map((e) => e.parentId)
          .whereType<String>()
          .toSet();
      Widget row(DocumentOutlineEntry entry) {
        final id = entry.reference.blockId;
        return Padding(
          padding: EdgeInsets.only(left: entry.depth * 12.0),
          child: Row(
            children: [
              if (parents.contains(id))
                IconButton(
                  key: ValueKey('smart-document.outline.fold.$id'),
                  tooltip: coordinator.collapsed(id) ? '展开子目录' : '收起子目录',
                  onPressed: () => coordinator.toggle(id),
                  icon: Icon(
                    coordinator.collapsed(id)
                        ? Icons.chevron_right
                        : Icons.expand_more,
                    size: 18,
                  ),
                )
              else
                const SizedBox(width: 48),
              Expanded(
                child: TextButton(
                  key: ValueKey('smart-document.outline.entry.$id'),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, 44),
                    backgroundColor: coordinator.activeId == id
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  onPressed: () async {
                    if (onNavigate != null) {
                      await onNavigate!(entry.reference);
                      return;
                    }
                    final ok = await coordinator.navigate(entry.reference);
                    if (!ok && context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('标题已变化或当前无法定位，请重试')),
                      );
                  },
                  child: Text(
                    entry.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      final children = [
        if (outline.warnings > 0)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('部分标题格式暂不支持，正文已保留'),
          ),
        ...entries.map(row),
      ];
      return scrollable
          ? ListView(children: children)
          : Column(children: children);
    },
  );
}
