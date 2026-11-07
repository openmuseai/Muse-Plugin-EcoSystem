import 'outline_view.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'realtime_session.dart';
import 'collaborators_view.dart';
import 'core_api.dart';
import 'link_commands.dart';
import 'link_ui.dart';
import 'media_session.dart';
import 'embedded_resources.dart';
import 'package:muse_resource_embed/muse_resource_embed.dart';
import 'image_components.dart';
import 'editor_components.dart';
import 'formula_components.dart';
import 'mobile_document_view.dart';

/// Phase-one production surface. Only implemented capabilities are exposed;
/// comments/share/history are introduced by later increments, not fake buttons.
final class SmartDocumentView extends StatefulWidget {
  const SmartDocumentView({
    super.key,
    required this.controller,
    required this.title,
    this.media,
    this.linkOpener,
    this.realtime,
    this.embeds,
  });
  final SmartDocumentController controller;
  final String title;
  final DocumentMediaSession? media;
  final DocumentLinkOpener? linkOpener;
  final DocumentRealtimeSession? realtime;
  final ResourceEmbedHost? embeds;

  @override
  State<SmartDocumentView> createState() => _SmartDocumentViewState();
}

final class _SmartDocumentViewState extends State<SmartDocumentView> {
  SmartDocumentController get controller => widget.controller;
  String get title => widget.title;
  late DocumentOutlineCoordinator _outline;
  bool _showOutline = false;
  @override
  void initState() {
    super.initState();
    _outline = DocumentOutlineCoordinator(controller);
  }

  @override
  void didUpdateWidget(covariant SmartDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      final old = _outline;
      old.deactivate();
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      _outline = DocumentOutlineCoordinator(controller);
      _showOutline = false;
    }
  }

  @override
  void dispose() {
    _outline.dispose();
    super.dispose();
  }

  List<DocumentBlockReference> _typeTargets = const [];
  DocumentBlockReference? _insertAfter;
  DocumentTextRange? _linkRange;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ResourceEmbedScope(
      host: widget.embeds,
      allowEditing: controller.canWrite,
      child: _buildSurface(context),
    ),
  );

  Widget _buildSurface(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 700) {
      return MobileSmartDocumentView(
        outline: _outline,
        controller: controller,
        title: title,
        media: widget.media,
        embeds: widget.embeds,
        linkOpener: widget.linkOpener,
        realtime: widget.realtime,
      );
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.canRead)
          return const Center(child: Text('文档访问已失效，本机副本保留'));
        final theme = Theme.of(context);
        final editor = controller.editor;
        final canEdit = controller.canWrite;
        final colors = theme.colorScheme;
        return ColoredBox(
          color: colors.surface,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined, color: colors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (widget.realtime != null)
                      DocumentCollaboratorsView(session: widget.realtime!),
                    if (!canEdit)
                      const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Text('只读'),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 3,
                  children: [
                    IconButton(
                      key: const ValueKey('smart-document.undo'),
                      tooltip: '撤销',
                      onPressed: canEdit && controller.canUndo
                          ? () => controller.history()
                          : null,
                      icon: const Icon(Icons.undo, size: 19),
                    ),
                    IconButton(
                      key: const ValueKey('smart-document.redo'),
                      tooltip: '重做',
                      onPressed: canEdit && controller.canRedo
                          ? () => controller.history(redo: true)
                          : null,
                      icon: const Icon(Icons.redo, size: 19),
                    ),
                    for (final (attribute, label, icon) in [
                      ('bold', '加粗', Icons.format_bold),
                      ('italic', '斜体', Icons.format_italic),
                      ('underline', '下划线', Icons.format_underlined),
                    ])
                      IconButton(
                        key: ValueKey('smart-document.$attribute'),
                        tooltip: label,
                        onPressed: canEdit
                            ? () => editor.toggleAttribute(attribute)
                            : null,
                        icon: Icon(icon, size: 19),
                      ),
                    IconButton(
                      key: const ValueKey('smart-document.link'),
                      tooltip: '超链接',
                      icon: const Icon(Icons.link, size: 19),
                      onPressed: canEdit
                          ? () => showDocumentLinkEditor(
                              context,
                              controller,
                              opener: widget.linkOpener,
                            )
                          : null,
                    ),
                    PopupMenuButton<String>(
                      key: const ValueKey('smart-document.block-type'),
                      requestFocus: false,
                      enabled: canEdit,
                      tooltip: '块类型',
                      icon: const Icon(Icons.text_fields, size: 19),
                      onOpened: () {
                        _typeTargets = controller.referencesForSelection();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'paragraph',
                          child: Text('正文'),
                        ),
                        for (var level = 1; level <= 6; level++)
                          PopupMenuItem(
                            value: 'heading:$level',
                            child: Text('标题 $level'),
                          ),
                        for (final (type, label) in const [
                          ('bulleted_list', '无序列表'),
                          ('numbered_list', '有序列表'),
                          ('todo_list', '待办'),
                          ('quote', '引用'),
                          ('code', '代码块'),
                        ])
                          PopupMenuItem(value: type, child: Text(label)),
                      ],
                      onSelected: (value) async {
                        final parts = value.split(':');
                        try {
                          await controller.convertBlocks(
                            _typeTargets,
                            parts.first,
                            level: parts.length == 2
                                ? int.parse(parts.last)
                                : null,
                          );
                        } on Object {
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('请选择有效的正文块后重试')),
                            );
                        }
                      },
                    ),
                    PopupMenuButton<String>(
                      key: const ValueKey('smart-document.insert'),
                      requestFocus: false,
                      enabled: canEdit,
                      tooltip: '插入内容',
                      onOpened: () {
                        _insertAfter = controller.insertionAnchor;
                        _linkRange = controller.captureTextRange();
                      },
                      icon: const Icon(Icons.add, size: 19),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'paragraph', child: Text('正文')),
                        PopupMenuItem(value: 'heading', child: Text('标题')),
                        PopupMenuItem(
                          value: 'bulleted_list',
                          child: Text('无序列表'),
                        ),
                        PopupMenuItem(value: 'todo_list', child: Text('任务列表')),
                        PopupMenuItem(value: 'quote', child: Text('引用')),
                        PopupMenuItem(value: 'table', child: Text('表格（2 × 2）')),
                        PopupMenuItem(value: 'link', child: Text('超链接')),
                        PopupMenuItem(value: 'formula', child: Text('公式')),
                        if (widget.embeds?.pick != null)
                          const PopupMenuItem(
                            value: 'database',
                            child: Text('数据库'),
                          ),
                        if (widget.media != null)
                          const PopupMenuItem(
                            value: 'image',
                            child: Text('图片'),
                          ),
                      ],
                      onSelected: (type) async {
                        if (type == 'formula') {
                          await showDocumentFormulaEditor(
                            context,
                            controller,
                            after: _insertAfter,
                          );
                          return;
                        }
                        if (type == 'database') {
                          await pickDocumentDatabase(
                            context,
                            controller,
                            widget.embeds,
                            after: _insertAfter,
                          );
                          return;
                        }
                        if (type == 'image') {
                          await insertDocumentImage(
                            context,
                            widget.media,
                            after: _insertAfter,
                          );
                          return;
                        }
                        if (type == 'link') {
                          await showDocumentLinkEditor(
                            context,
                            controller,
                            range: _linkRange,
                            opener: widget.linkOpener,
                          );
                          return;
                        }
                        if (type == 'table') {
                          try {
                            await controller.insertTable(after: _insertAfter);
                          } on Object {
                            if (context.mounted)
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('插入位置已变化，请重新选择位置'),
                                ),
                              );
                          }
                          return;
                        }
                        final transaction = editor.transaction;
                        final node = type == 'paragraph'
                            ? paragraphNode()
                            : Node(
                                type: type,
                                attributes: {
                                  'delta': [],
                                  if (type == 'heading') 'level': 1,
                                  if (type == 'todo_list') 'checked': false,
                                },
                              );
                        final path = editor.selection?.end.path;
                        final index = path != null && path.isNotEmpty
                            ? path.first + 1
                            : controller.blocks.length;
                        transaction.insertNode([index], node, deepCopy: false);
                        await editor.apply(transaction);
                      },
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (controller.failure != null)
                MaterialBanner(
                  key: const ValueKey('smart-document.failure'),
                  content: Text(
                    controller.contentFailure != null
                        ? '本次内容操作未提交。可以放弃该操作，恢复已保存内容。'
                        : controller.localSave == LocalSaveState.failed
                        ? '本机保存未完成，请保留当前页面并重试。'
                        : '协作暂不可用，本机修改仍保留。',
                  ),
                  actions: [
                    if (controller.contentFailure != null)
                      TextButton(
                        onPressed: controller.discardRejectedOperation,
                        child: const Text('放弃未提交操作'),
                      ),
                    TextButton(
                      onPressed: () async {
                        try {
                          await controller.flush();
                          await controller.synchronize();
                        } on Object {
                          /* The persistent error remains visible. */
                        }
                      },
                      child: const Text('重试'),
                    ),
                  ],
                ),
              DocumentMediaStatus(media: widget.media),
              Expanded(
                child: Row(
                  children: [
                    if (_showOutline)
                      SizedBox(
                        width: 232,
                        child: Column(
                          children: [
                            const SizedBox(
                              height: 48,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Padding(
                                  padding: EdgeInsets.only(left: 16),
                                  child: Text('目录'),
                                ),
                              ),
                            ),
                            Expanded(
                              child: DocumentOutlineView(coordinator: _outline),
                            ),
                          ],
                        ),
                      ),
                    if (_showOutline) const VerticalDivider(width: 1),
                    Expanded(
                      child: Center(
                        child: ConstrainedBox(
                          key: _outline.viewportKey,
                          constraints: const BoxConstraints(maxWidth: 840),
                          child: AppFlowyEditor(
                            key: const ValueKey('smart-document.editor'),
                            editorState: editor,
                            editorScrollController: _outline.scroll,
                            shrinkWrap: false,
                            editable: canEdit,
                            header: const SizedBox(height: 20),
                            footer: const SizedBox(height: 100),
                            commandShortcutEvents:
                                smartDocumentCommandShortcuts(
                                  editLink: () => showDocumentLinkEditor(
                                    context,
                                    controller,
                                    opener: widget.linkOpener,
                                  ),
                                ),
                            blockComponentBuilders: smartDocumentBlockBuilders(
                              controller,
                              media: widget.media,
                            ),
                            characterShortcutEvents:
                                smartDocumentCharacterShortcuts(
                                  controller,
                                  slash: customSlashCommand(
                                    standardSelectionMenuItems
                                        .where(
                                          (item) => !item.keywords.any(
                                            (keyword) =>
                                                keyword.contains('image') ||
                                                keyword.contains('table'),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ),
                            editorStyle: EditorStyle.desktop(
                              textSpanDecorator: documentLinkDecorator(
                                controller,
                                opener: widget.linkOpener,
                              ),
                              // This editor version applies style padding to each block.
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              cursorColor: colors.primary,
                              selectionColor: colors.primary.withValues(
                                alpha: .18,
                              ),
                              textStyleConfiguration: TextStyleConfiguration(
                                text: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 16,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('smart-document.outline.toggle'),
                      tooltip: _showOutline ? '隐藏目录' : '显示目录',
                      isSelected: _showOutline,
                      onPressed: () =>
                          setState(() => _showOutline = !_showOutline),
                      icon: const Icon(Icons.format_list_bulleted, size: 18),
                    ),
                    Expanded(
                      child: Text(
                        _status(controller),
                        key: const ValueKey('smart-document.status'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    if (controller.provider != null)
                      IconButton(
                        key: const ValueKey('smart-document.sync'),
                        tooltip: '立即同步',
                        onPressed: controller.synchronize,
                        icon: const Icon(Icons.sync, size: 18),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _status(SmartDocumentController controller) {
    final local = switch (controller.localSave) {
      LocalSaveState.dirty => '正在保存本机',
      LocalSaveState.durable => '已保存到本机',
      LocalSaveState.failed => '本机保存失败',
    };
    final sync = switch (controller.syncState) {
      DocumentSyncState.localOnly => '本机文档',
      DocumentSyncState.paused => '离线',
      DocumentSyncState.pending => '待同步',
      DocumentSyncState.exchanging => '正在同步',
      DocumentSyncState.accepted => '协作服务已接收',
      DocumentSyncState.failed => '协作暂不可用',
      DocumentSyncState.forbidden => '共享访问已失效',
      DocumentSyncState.removed => '云端文档已移除 · 本机副本保留',
    };
    return '$local · $sync';
  }
}
