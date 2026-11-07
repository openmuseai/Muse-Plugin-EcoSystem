import 'dart:async';
import 'dart:math' as math;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'realtime_session.dart';
import 'collaborators_view.dart';
import 'editor_components.dart';
import 'core_api.dart';
import 'link_commands.dart';
import 'link_ui.dart';
import 'media_session.dart';
import 'embedded_resources.dart';
import 'package:muse_resource_embed/muse_resource_embed.dart';
import 'image_components.dart';

/// Mobile surface of the same AppFlowy editor and domain CRDT session.
/// Scaffold owns the IME inset. This widget never adds a second keyboard inset.
final class MobileSmartDocumentView extends StatefulWidget {
  const MobileSmartDocumentView({
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
  State<MobileSmartDocumentView> createState() =>
      _MobileSmartDocumentViewState();
}

class _MobileSmartDocumentViewState extends State<MobileSmartDocumentView>
    with WidgetsBindingObserver {
  bool _editing = false;
  String? _panel;
  Selection? _savedSelection;
  int? _selectionRevision;
  DocumentBlockReference? _insertAfter;
  DocumentTextRange? _savedTextRange;
  final _agentDraft = TextEditingController();
  final _agentFocus = FocusNode();
  SmartDocumentController get c => widget.controller;
  EditorState get editor => c.editor;
  bool get _writable => c.canWrite;
  bool get _canEdit => _editing && _writable;
  bool get _popover => _panel == 'list' || _panel == 'align';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _agentDraft.dispose();
    _agentFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    // Scaffold removes the consumed IME inset from its body's MediaQuery.
    // Read the FlutterView for keyboard state; Scaffold still owns resizing.
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      // Failure remains visible on the controller; do not discard the session.
      unawaited(c.flush().catchError((Object _) {}));
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_canEdit) return;
    try {
      await action();
    } on Object {
      if (mounted) _message('操作未完成，请保留页面并重试');
    }
    if (mounted) setState(() {});
  }

  void _capture() {
    if (editor.selection != null) {
      try {
        _savedTextRange = c.captureTextRange();
      } on Object {
        _savedTextRange = null;
      }
      _savedSelection = editor.selection;
      _selectionRevision = c.revision;
    }
  }

  bool _restore() {
    if (editor.selection != null) return true;
    if (_savedSelection != null && _selectionRevision == c.revision) {
      editor.selection = _savedSelection;
      return true;
    }
    _message('请先在正文中选择要编辑的位置');
    return false;
  }

  void _keyboard() {
    if (!_canEdit) return;
    if (View.of(context).viewInsets.bottom > 0) {
      _capture();
      editor.service.keyboardService?.closeKeyboard();
    } else if (_restore()) {
      final selection = editor.selection!;
      // OS Back / external keyboards can hide IME without closing its client.
      // Reset the attachment so AppFlowy's equal-value fast path cannot skip show.
      editor.service.keyboardService?.closeKeyboard();
      editor.service.keyboardService?.enableKeyBoard(selection);
    }
    setState(() => _panel = null);
  }

  void _open(String name) {
    _capture();
    if (name == 'insert' || name == 'image') _insertAfter = c.insertionAnchor;
    if (_panel == name) {
      setState(() => _panel = null);
      return;
    }
    if (name != 'list' && name != 'align' && name != 'agent') {
      editor.service.keyboardService?.closeKeyboard();
      _agentFocus.unfocus();
    }
    setState(() => _panel = name);
    if (name == 'agent') _agentFocus.requestFocus();
  }

  Future<void> _beginEdit() async {
    if (!_writable) return;
    setState(() {
      _editing = true;
      _panel = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (editor.selection == null) {
      final node = c.blocks.last;
      editor.selection = Selection.collapsed(
        Position(path: node.path, offset: node.delta?.length ?? 0),
      );
    }
    editor.service.keyboardService?.enableKeyBoard(editor.selection!);
  }

  Future<void> _done() async {
    try {
      await c.flush();
      if (!mounted) return;
      _capture();
      editor.service.keyboardService?.closeKeyboard();
      _agentFocus.unfocus();
      setState(() {
        _editing = false;
        _panel = null;
      });
    } on Object {
      if (mounted) _message('本机保存未完成，请重试');
    }
  }

  Future<void> _type(String type, {int? level}) => _run(() async {
    if (!_restore()) return;
    await c.convertSelection(
      type,
      level: level,
      attachTextService: _panel != 'format',
    );
    _capture();
  });
  Future<void> _mark(String key, dynamic value) => _run(() async {
    if (!_restore()) return;
    final selection = editor.selection!;
    if (selection.isCollapsed) {
      editor.updateToggledStyle(key, value);
    } else {
      await editor.formatDelta(
        selection,
        {key: value},
        selectionExtraInfo: {selectionExtraInfoDoNotAttachTextService: true},
      );
    }
    _capture();
  });
  Future<void> _toggle(String key) => _run(() async {
    if (!_restore()) return;
    await editor.toggleAttribute(
      key,
      selectionExtraInfo: {selectionExtraInfoDoNotAttachTextService: true},
    );
    _capture();
  });
  Future<void> _align(String align) => _run(() async {
    if (!_restore()) return;
    await editor.updateNode(
      editor.selection,
      (node) => node.copyWith(
        attributes: {...node.attributes, blockComponentAlign: align},
      ),
    );
    _capture();
  });
  Future<void> _insert(String type) => _run(() async {
    if (type == 'database') {
      if (mounted) setState(() => _panel = null);
      await pickDocumentDatabase(
        context,
        c,
        widget.embeds,
        after: _insertAfter,
      );
      return;
    }
    if (type == 'image') {
      if (mounted) setState(() => _panel = null);
      await insertDocumentImage(context, widget.media, after: _insertAfter);
      return;
    }
    if (type == 'link') {
      if (mounted) setState(() => _panel = null);
      await showDocumentLinkEditor(
        context,
        c,
        range: _savedTextRange,
        opener: widget.linkOpener,
      );
      return;
    }
    if (type == 'table') {
      await c.insertTable(after: _insertAfter, attachTextService: false);
      _capture();
      if (mounted) setState(() => _panel = null);
      return;
    }
    final path = editor.selection?.end.path ?? _savedSelection?.end.path;
    final index = path?.isNotEmpty == true ? path!.first + 1 : c.blocks.length;
    final node = type == 'paragraph'
        ? paragraphNode()
        : Node(
            type: type,
            attributes: {
              if (type != 'divider') 'delta': [],
              if (type == 'code') 'language': 'plain text',
            },
          );
    final tx = editor.transaction
      ..insertNode([index], node, deepCopy: false)
      ..afterSelection = Selection.collapsed(Position(path: [index]));
    await editor.apply(tx);
    _capture();
    if (mounted) setState(() => _panel = null);
  });
  Widget _button(
    String label,
    IconData icon,
    VoidCallback? action, {
    String? id,
  }) => SizedBox(
    width: 44,
    height: 48,
    child: IconButton(
      key: ValueKey('smart-document.mobile.${id ?? label}'),
      tooltip: label,
      onPressed: action,
      icon: Icon(icon, size: 23),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => ResourceEmbedScope(
      host: widget.embeds,
      allowEditing: _canEdit,
      child: _buildSurface(context),
    ),
  );

  Widget _buildSurface(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      c,
      editor.selectionNotifier,
      editor.toggledStyleNotifier,
    ]),
    builder: (context, _) {
      if (!c.canRead)
        return const SafeArea(child: Center(child: Text('文档访问已失效，本机副本保留')));
      final colors = Theme.of(context).colorScheme;
      final keyboard = View.of(context).viewInsets.bottom > 0;
      return PopScope(
        canPop: _panel == null && !_editing,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_panel != null) {
            _agentFocus.unfocus();
            setState(() => _panel = null);
          } else {
            unawaited(_done());
          }
        },
        child: SafeArea(
          child: ColoredBox(
            color: colors.surface,
            child: Column(
              children: [
                if (_panel != 'agent')
                  SizedBox(
                    height: 52,
                    child: Row(
                      children: [
                        if (_editing) ...[
                          TextButton(
                            key: const ValueKey('smart-document.mobile.done'),
                            onPressed: _done,
                            child: const Text('完成'),
                          ),
                          _button(
                            '撤销',
                            Icons.undo,
                            _writable && c.canUndo
                                ? () => _run(() => c.history())
                                : null,
                            id: 'undo',
                          ),
                          _button(
                            '重做',
                            Icons.redo,
                            _writable && c.canRedo
                                ? () => _run(() => c.history(redo: true))
                                : null,
                            id: 'redo',
                          ),
                        ] else ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: CircleAvatar(
                              radius: 15,
                              child: Icon(Icons.person_outline, size: 19),
                            ),
                          ),
                          const Spacer(),
                          if (widget.realtime != null)
                            DocumentCollaboratorsView(
                              session: widget.realtime!,
                            ),
                          _button('分享', Icons.ios_share, null),
                          _button('评论', Icons.mode_comment_outlined, null),
                        ],
                        if (_editing) const Spacer(),
                        _button('更多', Icons.menu, () => _open('more')),
                      ],
                    ),
                  ),
                const Divider(height: 1),
                if (c.failure != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.contentFailure != null
                                ? '本次内容操作未提交，可放弃该操作后继续'
                                : c.localSave == LocalSaveState.failed
                                ? '本机保存失败，请保留当前页面'
                                : '协作暂不可用，本机修改仍保留',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (c.contentFailure != null)
                          TextButton(
                            onPressed: c.discardRejectedOperation,
                            child: const Text('放弃未提交操作'),
                          ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await c.flush();
                              await c.synchronize();
                            } on Object {
                              /* state stays visible */
                            }
                          },
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                DocumentMediaStatus(media: widget.media),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AppFlowyEditor(
                          key: const ValueKey('smart-document.editor'),
                          editorState: editor,
                          editable: _canEdit,
                          shrinkWrap: false,
                          header: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontSize: 29,
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                Text(
                                  _status(),
                                  key: const ValueKey('smart-document.status'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          footer: const SizedBox(height: 80),
                          commandShortcutEvents: smartDocumentCommandShortcuts(
                            editLink: () => showDocumentLinkEditor(
                              context,
                              c,
                              opener: widget.linkOpener,
                            ),
                          ),
                          blockComponentBuilders: smartDocumentBlockBuilders(
                            c,
                            media: widget.media,
                          ),
                          characterShortcutEvents:
                              smartDocumentCharacterShortcuts(c),
                          editorStyle: EditorStyle.mobile(
                            textSpanDecorator: documentLinkDecorator(
                              c,
                              opener: widget.linkOpener,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            cursorColor: colors.primary,
                            selectionColor: colors.primary.withValues(
                              alpha: .18,
                            ),
                            textStyleConfiguration: TextStyleConfiguration(
                              text: TextStyle(
                                fontSize: 16,
                                height: 1.65,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (!_editing)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: Material(
                            elevation: 3,
                            borderRadius: BorderRadius.circular(30),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  _dock(
                                    '编辑',
                                    Icons.edit_outlined,
                                    _writable ? _beginEdit : null,
                                  ),
                                  _dock(
                                    '聊文档',
                                    Icons.auto_awesome_outlined,
                                    () => _open('agent'),
                                  ),
                                  _dock(
                                    '目录',
                                    Icons.format_list_bulleted,
                                    () => _open('outline'),
                                  ),
                                  _dock('视图', Icons.tune, () => _open('view')),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_panel == 'agent')
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(14),
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (final label in [
                                      'AI 帮我写',
                                      '润色',
                                      '扩写',
                                      '缩写',
                                      '语病修正',
                                    ])
                                      ListTile(
                                        dense: true,
                                        title: Text(label),
                                        enabled: false,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_popover)
                        Positioned(
                          bottom: 8,
                          left: _panel == 'list'
                              ? math.max(
                                  8,
                                  MediaQuery.sizeOf(context).width / 2 - 70,
                                )
                              : null,
                          right: _panel == 'align' ? 8 : null,
                          child: Material(
                            key: ValueKey('smart-document.mobile.${_panel}'),
                            elevation: 5,
                            borderRadius: BorderRadius.circular(11),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: _popoverContent(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (_panel == 'agent')
                  _agentComposer()
                else ...[
                  if (_panel != null && !_popover) _sheet(),
                  if (_editing)
                    Focus(
                      canRequestFocus: false,
                      descendantsAreFocusable: false,
                      child: Container(
                        key: const ValueKey('smart-document.mobile.tools'),
                        height: 52,
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(color: colors.outlineVariant),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, box) =>
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children: [
                                          for (final (label, icon, panel)
                                              in const [
                                                (
                                                  'AI 助手',
                                                  Icons.auto_awesome,
                                                  'agent',
                                                ),
                                                (
                                                  '插入',
                                                  Icons.add_circle_outline,
                                                  'insert',
                                                ),
                                                (
                                                  '调整样式',
                                                  Icons.text_fields,
                                                  'format',
                                                ),
                                                (
                                                  '列表',
                                                  Icons.format_list_bulleted,
                                                  'list',
                                                ),
                                                (
                                                  '对齐',
                                                  Icons.format_align_left,
                                                  'align',
                                                ),
                                                (
                                                  '图片',
                                                  Icons.image_outlined,
                                                  'image',
                                                ),
                                                (
                                                  '@ 用户提及',
                                                  Icons.alternate_email,
                                                  'mention',
                                                ),
                                              ])
                                            SizedBox(
                                              width: math.max(
                                                44,
                                                box.maxWidth / 7,
                                              ),
                                              child: _button(
                                                label,
                                                icon,
                                                _canEdit
                                                    ? () => _open(panel)
                                                    : null,
                                                id: panel,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                              ),
                            ),
                            _button(
                              keyboard ? '收起键盘' : '展开键盘',
                              keyboard
                                  ? Icons.keyboard_hide_outlined
                                  : Icons.keyboard_outlined,
                              _canEdit ? _keyboard : null,
                              id: 'keyboard',
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _dock(String label, IconData icon, VoidCallback? action) => SizedBox(
    width: 56,
    height: 56,
    child: TextButton(
      onPressed: action,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21),
          Text(label, style: const TextStyle(fontSize: 10)),
        ],
      ),
    ),
  );
  String _status() =>
      '${switch (c.localSave) {
        LocalSaveState.dirty => '正在保存本机',
        LocalSaveState.durable => '已保存到本机',
        LocalSaveState.failed => '本机保存失败',
      }} · ${switch (c.syncState) {
        DocumentSyncState.localOnly => '本机文档',
        DocumentSyncState.paused => '离线',
        DocumentSyncState.pending => '待同步',
        DocumentSyncState.exchanging => '正在同步',
        DocumentSyncState.accepted => '协作服务已接收',
        DocumentSyncState.failed => '协作暂不可用',
        DocumentSyncState.forbidden => '共享访问已失效',
        DocumentSyncState.removed => '云端文档已移除 · 本机副本保留',
      }}';
  Widget _popoverContent() => Focus(
    canRequestFocus: false,
    descendantsAreFocusable: false,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: _panel == 'list'
          ? [
              _button(
                '有序列表',
                Icons.format_list_numbered,
                () => _type('numbered_list'),
              ),
              _button(
                '无序列表',
                Icons.format_list_bulleted,
                () => _type('bulleted_list'),
              ),
              _button('待办', Icons.check_box_outlined, () => _type('todo_list')),
            ]
          : [
              _button('左对齐', Icons.format_align_left, () => _align('left')),
              _button(
                '居中对齐',
                Icons.format_align_center,
                () => _align('center'),
              ),
              _button('右对齐', Icons.format_align_right, () => _align('right')),
              const SizedBox(height: 24, child: VerticalDivider(width: 8)),
              _button(
                '减少缩进',
                Icons.format_indent_decrease,
                !smartDocumentInTable(editor) && isOutdentable(editor)
                    ? () => _run(() async {
                        outdentCommand.execute(editor);
                        _capture();
                      })
                    : null,
              ),
              _button(
                '增加缩进',
                Icons.format_indent_increase,
                !smartDocumentInTable(editor) && isIndentable(editor)
                    ? () => _run(() async {
                        indentCommand.execute(editor);
                        _capture();
                      })
                    : null,
              ),
            ],
    ),
  );
  Widget _sheet() {
    final title = switch (_panel) {
      'format' => '调整样式',
      'insert' => '插入',
      'outline' => '目录',
      'view' => '视图',
      'more' => '文件与更多',
      'mention' => '@ 用户',
      'image' => '图片',
      _ => '功能',
    };
    return SizedBox(
      height: math.min(400, MediaQuery.sizeOf(context).height * .47),
      child: Material(
        key: ValueKey('smart-document.mobile.panel.$_panel'),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Row(
                children: [
                  const SizedBox(width: 44),
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _button(
                    '关闭面板',
                    Icons.close,
                    () => setState(() => _panel = null),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _panelContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panelContent() => switch (_panel) {
    'format' => _format(),
    'insert' => Column(
      children: [
        if (widget.embeds?.pick != null)
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('数据库'),
            onTap: () => _insert('database'),
          ),
        if (widget.media != null)
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('图片'),
            onTap: () => _insert('image'),
          ),
        for (final (label, type) in const [
          ('正文', 'paragraph'),
          ('引用', 'quote'),
          ('代码块', 'code'),
          ('分隔线', 'divider'),
          ('超链接', 'link'),
        ])
          ListTile(title: Text(label), onTap: () => _insert(type)),
        ListTile(
          title: const Text('表格'),
          subtitle: const Text('2 × 2'),
          onTap: () => _insert('table'),
        ),
        for (final label in ['云文档', '本地文件', '视频'])
          ListTile(
            title: Text(label),
            subtitle: const Text('暂不可用'),
            enabled: false,
          ),
      ],
    ),
    'image' => Column(
      children: [
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('选择图片'),
          subtitle: const Text('PNG、JPEG、GIF、WebP，最大 12 MB'),
          enabled: widget.media != null,
          onTap: () => _insert('image'),
        ),
      ],
    ),
    'outline' => Column(
      children: [
        for (final node in editor.document.root.children.where(
          (n) => n.type == 'heading',
        ))
          ListTile(
            title: Text(node.delta?.toPlainText() ?? ''),
            onTap: () {
              setState(() => _panel = null);
              editor.scrollService?.jumpTo(node.path.first);
            },
          ),
      ],
    ),
    'view' => const Padding(
      padding: EdgeInsets.all(16),
      child: Text('连续阅读 · 适应屏幕\n文字大小跟随系统设置'),
    ),
    'more' => Column(
      children: [
        Text(widget.title),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('立即同步'),
          enabled: c.provider != null,
          onTap: () => c.synchronize(),
        ),
        for (final label in [
          '另存',
          '分享',
          '打印',
          '页面设置',
          '查找替换',
          '导出为 Word (.docx)',
          '导出为其他格式',
          '分享文档模板',
          '保存版本',
          '历史版本',
          '历史评论',
        ])
          ListTile(
            title: Text(label),
            subtitle: const Text('暂不可用'),
            enabled: false,
          ),
      ],
    ),
    'mention' => const Padding(
      padding: EdgeInsets.all(16),
      child: Text('用户提及暂不可用'),
    ),
    _ => const SizedBox.shrink(),
  };
  Widget _format() => Focus(
    canRequestFocus: false,
    descendantsAreFocusable: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('文本类型'),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, box) => Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final level in [1, 2, 3, 4, 5, 6, 0])
                SizedBox(
                  width: (box.maxWidth - 24) / 4,
                  height: 48,
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      textStyle: const TextStyle(fontSize: 16),
                    ),
                    onPressed: () => _type(
                      level == 0 ? 'paragraph' : 'heading',
                      level: level == 0 ? null : level,
                    ),
                    child: Text(
                      level == 0 ? '正文' : '标题 $level',
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text('文本样式'),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final (key, label, icon) in const [
              ('bold', '加粗', Icons.format_bold),
              ('italic', '斜体', Icons.format_italic),
              ('underline', '下划线', Icons.format_underlined),
              ('strikethrough', '删除线', Icons.strikethrough_s),
            ])
              _button(
                label,
                icon,
                key == 'bold' &&
                        editor
                                .getNodeAtPath(
                                  editor.selection?.start.path ?? [],
                                )
                                ?.attributes['level'] ==
                            1
                    ? null
                    : () => _toggle(key),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('字体颜色'),
        _palette(AppFlowyRichTextKeys.textColor, const [
          null,
          0xff242424,
          0xff919191,
          0xffcb3e43,
          0xffe77938,
          0xffdbad32,
          0xff62a34d,
          0xff399d8e,
          0xff3c8bc9,
          0xff426cba,
          0xff6559ba,
          0xffa358ae,
          0xffb65784,
          0xff764f3f,
          0xff5f6e7e,
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text('渐变字体颜色暂不可用', style: TextStyle(fontSize: 12)),
        ),
        const Text('高亮颜色'),
        _palette(AppFlowyRichTextKeys.backgroundColor, const [
          null,
          0xfffaedb1,
          0xfff8ddba,
          0xfff6d3d8,
          0xffd4eac5,
          0xffc5e7df,
          0xffcde6fa,
          0xffd5def9,
          0xffe7d5f3,
          0xffe6e6e6,
        ]),
      ],
    ),
  );
  Widget _palette(String key, List<int?> colors) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final color in colors)
          SizedBox(
            key: ValueKey('smart-document.mobile.color.$key.$color'),
            width: 48,
            height: 44,
            child: Semantics(
              label: color == null
                  ? '清除${key == AppFlowyRichTextKeys.textColor ? '字体颜色' : '高亮'}'
                  : '${key == AppFlowyRichTextKeys.textColor ? '字体颜色' : '高亮'} ${color.toRadixString(16)}',
              button: true,
              child: InkWell(
                onTap: () =>
                    _mark(key, color == null ? null : Color(color).toHex()),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    color:
                        key == AppFlowyRichTextKeys.backgroundColor &&
                            color != null
                        ? Color(color)
                        : null,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: color == null
                      ? const Icon(Icons.format_color_reset, size: 23)
                      : Text(
                          'A',
                          style: TextStyle(
                            fontSize: 24,
                            color: key == AppFlowyRichTextKeys.textColor
                                ? Color(color)
                                : Colors.black87,
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _agentComposer() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _button('退出 AI', Icons.arrow_back, () {
              _agentFocus.unfocus();
              setState(() => _panel = null);
            }),
            Expanded(
              child: TextField(
                key: const ValueKey('smart-document.mobile.agent-input'),
                controller: _agentDraft,
                focusNode: _agentFocus,
                decoration: const InputDecoration(
                  hintText: '从下方选择功能或直接输入',
                  border: InputBorder.none,
                ),
              ),
            ),
            _button('发送', Icons.arrow_upward, null),
          ],
        ),
      ),
      Container(
        height: 2,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff69b1f8), Color(0xff8c66ed), Color(0xffe89bc9)],
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.all(8),
        child: Text('AI 助手暂不可用', style: TextStyle(fontSize: 12)),
      ),
    ],
  );
}
