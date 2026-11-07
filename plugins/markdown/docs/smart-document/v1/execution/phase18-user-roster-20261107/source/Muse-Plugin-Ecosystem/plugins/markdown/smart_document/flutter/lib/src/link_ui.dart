import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'controller.dart';
import 'link_commands.dart';

typedef DocumentLinkOpener = Future<bool> Function(Uri target);

Future<bool> openDocumentLink(
  SmartDocumentController c,
  String target, {
  DocumentLinkOpener? opener,
}) async {
  c.core.call({'action': 'validateLink', 'handle': c.handle, 'href': target});
  final uri = Uri.parse(target);
  if (opener != null) return opener(uri);
  if (!{'http', 'https', 'mailto', 'tel'}.contains(uri.scheme)) return false;
  return launchUrl(uri);
}

/// Thin interaction adapter over original href rendering and domain commands.
/// The dialog owns draft fields; the domain owns anchors, validation and undo.
Future<void> showDocumentLinkEditor(
  BuildContext context,
  SmartDocumentController c, {
  DocumentTextRange? range,
  DocumentLinkOpener? opener,
}) async {
  try {
    range ??= c.captureTextRange();
  } on Object {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('选中的内容已变化，请重新选择')));
    return;
  }
  if (range == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先在正文中选择文字或输入位置')));
    return;
  }
  if (!c.canWrite || !c.editor.editable) return;
  String? existing;
  try {
    existing = c.linkAtRange(range);
  } on Object {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('选中的内容已变化，请重新选择')));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _LinkDialog(
      controller: c,
      range: range!,
      existing: existing,
      opener: opener,
    ),
  );
}

TextSpanDecoratorForAttribute documentLinkDecorator(
  SmartDocumentController c, {
  DocumentLinkOpener? opener,
}) => (context, node, index, text, before, after) {
  final href = text.attributes?['href'] as String?;
  if (href == null) return before;
  return TextSpan(
    text: text.text,
    style: before.style?.merge(
      TextStyle(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
    ),
    mouseCursor: SystemMouseCursors.click,
    recognizer: TapGestureRecognizer()
      ..onTap = () async {
        try {
          if (!c.editor.editable ||
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed) {
            final opened = await openDocumentLink(c, href, opener: opener);
            if (!opened && context.mounted)
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('此链接需要对应资源插件才能打开')));
          } else {
            final selection = Selection.single(
              path: node.path,
              startOffset: index,
              endOffset: index + text.text.length,
            );
            await showDocumentLinkEditor(
              context,
              c,
              range: c.captureTextRange(selection),
              opener: opener,
            );
          }
        } on Object {
          if (context.mounted)
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('链接暂时无法打开')));
        }
      },
  );
};

class _LinkDialog extends StatefulWidget {
  const _LinkDialog({
    required this.controller,
    required this.range,
    this.existing,
    this.opener,
  });
  final SmartDocumentController controller;
  final DocumentTextRange range;
  final String? existing;
  final DocumentLinkOpener? opener;
  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final _address = TextEditingController(text: widget.existing ?? '');
  late final _label = TextEditingController(text: widget.range.text);
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _address.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _apply({bool remove = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final address = _address.text.trim();
      final label = _label.text.isEmpty ? address : _label.text;
      await widget.controller.applyLink(
        widget.range,
        href: remove ? null : address,
        label: remove || label == widget.range.text ? null : label,
      );
      if (mounted) Navigator.of(context).pop();
    } on Object catch (error) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = error.toString().contains('LINK_TEXT_CHANGED')
              ? '文字已被修改，请取消后重新选择，避免覆盖协作者内容'
              : '链接或选区无效，请检查后重试';
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      key: const ValueKey('smart-document.link-dialog'),
      title: Text(widget.existing == null ? '插入超链接' : '编辑超链接'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('smart-document.link-address'),
                controller: _address,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: '链接地址',
                  hintText: 'https://example.com',
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('smart-document.link-label'),
                controller: _label,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '显示文字'),
              ),
              if (widget.existing != null)
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              try {
                                final opened = await openDocumentLink(
                                  widget.controller,
                                  _address.text,
                                  opener: widget.opener,
                                );
                                if (!opened && mounted)
                                  setState(() => _error = '此链接需要对应资源插件才能打开');
                              } on Object {
                                if (mounted)
                                  setState(() => _error = '链接地址无效，请检查后重试');
                              }
                            },
                      child: const Text('打开链接'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Clipboard.setData(
                              ClipboardData(text: _address.text),
                            ),
                      child: const Text('复制链接'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            key: const ValueKey('smart-document.link-remove'),
            onPressed: _busy ? null : () => _apply(remove: true),
            child: const Text('移除链接'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('smart-document.link-apply'),
          onPressed: _busy ? null : _apply,
          child: Text(_busy ? '正在应用…' : '应用'),
        ),
      ],
    ),
  );
}
