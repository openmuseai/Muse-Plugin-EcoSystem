import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:muse_resource_embed/muse_resource_embed.dart';
import 'controller.dart';
import 'core_api.dart';

extension SmartDocumentEmbedCommands on SmartDocumentController {
  Future<DocumentBlockReference> insertDatabaseView(
    ResourceEmbedTarget target, {
    DocumentBlockReference? after,
  }) async {
    if (target.surface != 'dataset.grid' ||
        target.selector['viewId'] == null ||
        target.selector['objectId'] == null) {
      throw const SmartDocumentFailure('UNSUPPORTED_EMBED_SURFACE');
    }
    var index = blocks.length;
    if (after != null) {
      final node = resolveBlock(after);
      if (node == null || node.path.length != 1) {
        throw const SmartDocumentFailure('TARGET_MISSING');
      }
      index = node.path.first + 1;
    }
    final node = Node(
      type: 'grid',
      attributes: {
        'parent_id': objectId,
        'view_id': target.selector['viewId'],
        'muse_embed': target.toJson(),
      },
    );
    await executeDomainOperations([
      {
        'op': 'insert',
        'path': [index],
        'nodes': [
          {'id': node.id, 'type': node.type, 'data': node.attributes},
        ],
      },
    ]);
    return DocumentBlockReference(objectId: objectId, blockId: node.id);
  }

  Future<void> removeDatabaseView(DocumentBlockReference reference) async {
    final node = resolveBlock(reference);
    if (node == null || !{'grid', 'board', 'calendar'}.contains(node.type)) {
      throw const SmartDocumentFailure('TARGET_MISSING');
    }
    await executeDomainOperations([
      {'op': 'delete', 'path': node.path},
    ]);
  }
}

Future<void> pickDocumentDatabase(
  BuildContext context,
  SmartDocumentController controller,
  ResourceEmbedHost? host, {
  DocumentBlockReference? after,
}) async {
  if (host?.pick == null) return;
  try {
    final target = await host!.pick!(context, 'dataset.grid');
    if (target != null)
      await controller.insertDatabaseView(target, after: after);
  } on Object {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('数据库未能插入，请检查访问权限或重新选择位置')));
  }
}

/// Adapts the original inline database block; child content is contributed by a
/// separately installed resource plugin. No dataset or transport imports here.
final class DocumentDatabaseBuilder extends BlockComponentBuilder {
  DocumentDatabaseBuilder(this.controller);
  final SmartDocumentController controller;
  @override
  BlockComponentValidate get validate =>
      (n) =>
          n.children.isEmpty &&
          n.attributes['parent_id'] is String &&
          n.attributes['view_id'] is String;
  @override
  BlockComponentWidget build(BlockComponentContext context) => _EmbeddedBlock(
    key: context.node.key,
    node: context.node,
    configuration: configuration,
    controller: controller,
  );
}

class _EmbeddedBlock extends BlockComponentStatefulWidget {
  const _EmbeddedBlock({
    super.key,
    required super.node,
    required super.configuration,
    required this.controller,
  });
  final SmartDocumentController controller;
  @override
  State<_EmbeddedBlock> createState() => _EmbeddedBlockState();
}

class _EmbeddedBlockState extends State<_EmbeddedBlock> with SelectableMixin {
  final _childBounds = GlobalKey();
  late final _gestureKey = 'embedded-resource-${identityHashCode(this)}';
  AppFlowySelectionService? _selectionService;
  bool _outsideChild(Offset global) {
    final box = _childBounds.currentContext?.findRenderObject();
    return box is! RenderBox ||
        !box.paintBounds.contains(box.globalToLocal(global));
  }

  @override
  void initState() {
    super.initState();
    // Reuse the original selection interceptor, with one registration per
    // surface. A parent selection recognizer must not claim a child's blank
    // areas or headings after its focus has already moved to the child.
    _selectionService = widget.controller.editor.service.selectionService;
    _selectionService?.registerGestureInterceptor(
      SelectionGestureInterceptor(
        key: _gestureKey,
        canTap: (d) => _outsideChild(d.globalPosition),
        canDoubleTap: (d) => _outsideChild(d.globalPosition),
        canPanStart: (d) => _outsideChild(d.globalPosition),
      ),
    );
  }

  static final _focusedChildren = Expando<Set<Object>>(
    'document embedded focus owners',
  );
  bool _childHasFocus = false;
  void _focusChanged(bool focused) {
    _childHasFocus = focused;
    final editor = widget.controller.editor;
    final owners = _focusedChildren[editor] ??= <Object>{};
    if (focused) {
      owners.add(this);
      editor.selection = null;
      editor.service.keyboardService?.disableShortcuts();
    } else {
      owners.remove(this);
      if (owners.isEmpty) editor.service.keyboardService?.enableShortcuts();
    }
  }

  @override
  void dispose() {
    _selectionService?.unregisterGestureInterceptor(_gestureKey);
    if (_childHasFocus) _focusChanged(false);
    super.dispose();
  }

  Node get node => widget.node;
  @override
  Widget build(BuildContext context) {
    ResourceEmbedTarget? target;
    try {
      target = ResourceEmbedTarget.fromJson(node.attributes['muse_embed']);
    } on Object {
      /* Preserve unsupported upstream locators without guessing. */
    }
    final c = widget.controller;
    final host = ResourceEmbedScope.of(context);
    final policy = ResourceEmbedPolicy(
      allowEditing: c.canWrite && ResourceEmbedScope.editingAllowed(context),
    );
    return BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: c.editor.selectionNotifier,
      remoteSelection: c.editor.remoteSelections,
      blockColor: c.editor.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              if (policy.allowEditing)
                Align(
                  alignment: Alignment.centerRight,
                  child: PopupMenuButton<String>(
                    key: ValueKey('smart-document.embed-menu.${node.id}'),
                    tooltip: '数据库引用操作',
                    requestFocus: false,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'remove', child: Text('移除引用')),
                    ],
                    onSelected: (_) async {
                      try {
                        await c.removeDatabaseView(
                          DocumentBlockReference(
                            objectId: c.objectId,
                            blockId: node.id,
                          ),
                        );
                      } on Object {
                        if (context.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('移除未完成，请重试')),
                          );
                      }
                    },
                    icon: const Icon(Icons.more_horiz),
                  ),
                ),
              SizedBox(
                key: _childBounds,
                height: 360,
                child: target == null || host == null
                    ? const Center(child: Text('数据库引用暂不可用，原引用保留'))
                    : FocusScope(
                        skipTraversal: true,
                        onFocusChange: _focusChanged,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {},
                          child: host.build(context, target, policy),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
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
  }) => [getBlockRect()];
  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) => getBlockRect();
  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      box?.localToGlobal(offset) ?? offset;
}
