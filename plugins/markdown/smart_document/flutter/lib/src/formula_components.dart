import 'dart:convert';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:uuid/uuid.dart';
import 'controller.dart';
import 'core_api.dart';
import 'formula_commands.dart';

/// Same pure Flutter renderer/version used by the pinned AppFlowy client.
/// Source is retained even when this bounded rendering profile cannot display it.
class DocumentFormulaRenderer extends StatelessWidget {
  const DocumentFormulaRenderer(this.formula, {super.key});
  final String formula;
  static bool canRender(String source) {
    if (utf8.encode(source).length > 8192 ||
        RegExp(
          r'\\(?:href|url|includegraphics|htmlClass|htmlId|htmlStyle|htmlData|def|gdef|edef|xdef|let|newcommand|renewcommand|rule|kern|mkern|hspace|vspace|raisebox|fontsize)\b',
        ).hasMatch(source))
      return false;
    if (RegExp(r'\\[a-zA-Z]+').allMatches(source).length > 256) return false;
    var depth = 0;
    bool escaped = false;
    for (final c in source.codeUnits) {
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == 92) {
        escaped = true;
        continue;
      }
      if (c == 123 && ++depth > 64) return false;
      if (c == 125) depth--;
    }
    return true;
  }

  Widget _fallback() => const Text(
    '公式暂不能渲染，原文保留',
    key: ValueKey('smart-document.formula-fallback'),
  );
  @override
  Widget build(BuildContext context) {
    if (formula.isEmpty) return const Text('点击编辑公式');
    if (!canRender(formula)) return _fallback();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52, maxHeight: 200),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Math.tex(
          formula,
          textStyle: TextStyle(
            fontSize: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          settings: const TexParserSettings(maxExpand: 1000),
          onErrorFallback: (_) => _fallback(),
        ),
      ),
    );
  }
}

Future<void> showDocumentFormulaEditor(
  BuildContext context,
  SmartDocumentController c, {
  DocumentBlockReference? reference,
  DocumentBlockReference? after,
}) async {
  if (!c.canRead) return;
  DocumentFormulaDraft? draft;
  try {
    if (reference != null) draft = c.captureFormula(reference);
  } on Object {
    if (context.mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('公式已变化或不可用')));
    return;
  }
  if (!context.mounted) return;
  final keyboard = c.editor.service.keyboardService;
  keyboard?.disableShortcuts();
  try {
    await showDialog<void>(
      context: context,
      builder: (_) => _FormulaEditor(controller: c, draft: draft, after: after),
    );
  } finally {
    if (!c.editor.isDisposed) keyboard?.enableShortcuts();
  }
}

class _FormulaEditor extends StatefulWidget {
  const _FormulaEditor({required this.controller, this.draft, this.after});
  final SmartDocumentController controller;
  final DocumentFormulaDraft? draft;
  final DocumentBlockReference? after;
  @override
  State<_FormulaEditor> createState() => _FormulaEditorState();
}

class _FormulaEditorState extends State<_FormulaEditor> {
  late final input = TextEditingController(
    text: widget.draft?.formula ?? r'E=mc^2',
  );
  final focus = FocusNode();
  final insertId = const Uuid().v4();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    focus.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> apply({bool remove = false}) async {
    final c = widget.controller;
    if (busy || !c.canWrite || !c.editor.editable) return;
    if (!remove && widget.draft?.formula == input.text) {
      Navigator.pop(context);
      return;
    }
    if (!remove && utf8.encode(input.text).length > 8192) {
      setState(() => error = '公式源最多 8192 字节，请缩短后再应用');
      focus.requestFocus();
      return;
    }
    final epoch = c.localMutationEpoch;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (remove) {
        await c.deleteFormula(widget.draft!);
      } else if (widget.draft != null) {
        await c.updateFormula(widget.draft!, input.text);
      } else {
        await c.insertFormula(
          input.text,
          after: widget.after,
          blockId: insertId,
        );
      }
      if (mounted) Navigator.pop(context);
    } on Object {
      if (!mounted) return;
      if (c.persistenceFailure != null && c.localMutationEpoch > epoch) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        busy = false;
        error = '公式、位置或权限已变化；草稿已保留，请重新打开确认';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) focus.requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller, writable = c.canWrite && c.editor.editable;
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          key: const ValueKey('smart-document.formula-dialog'),
          scrollable: true,
          title: Text(
            writable ? (widget.draft == null ? '插入公式' : '编辑公式') : '公式源',
          ),
          content: !c.canRead
              ? const Text('无法访问此文档')
              : SizedBox(
                  width: 440,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        key: const ValueKey('smart-document.formula-input'),
                        controller: input,
                        focusNode: focus,
                        autofocus: writable,
                        readOnly: !writable || busy,
                        minLines: 3,
                        maxLines: 6,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.multiline,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'LaTeX 公式源',
                          errorText: error,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('预览'),
                      const SizedBox(height: 8),
                      DocumentFormulaRenderer(input.text),
                    ],
                  ),
                ),
          actions: [
            if (widget.draft != null && writable)
              TextButton(
                key: const ValueKey('smart-document.formula-delete'),
                onPressed: busy ? null : () => apply(remove: true),
                child: const Text('删除公式'),
              ),
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            if (writable)
              FilledButton(
                key: const ValueKey('smart-document.formula-apply'),
                onPressed: busy ? null : apply,
                child: const Text('应用'),
              ),
          ],
        ),
      );
    },
  );
}

final class DocumentFormulaBuilder extends BlockComponentBuilder {
  DocumentFormulaBuilder(this.controller);
  final SmartDocumentController controller;
  @override
  BlockComponentValidate get validate =>
      (n) => n.children.isEmpty && n.attributes['formula'] is String;
  @override
  BlockComponentWidget build(BlockComponentContext context) => _FormulaBlock(
    key: context.node.key,
    node: context.node,
    configuration: configuration,
    controller: controller,
  );
}

class _FormulaBlock extends BlockComponentStatefulWidget {
  const _FormulaBlock({
    super.key,
    required super.node,
    required super.configuration,
    required this.controller,
  });
  final SmartDocumentController controller;
  @override
  State<_FormulaBlock> createState() => _FormulaBlockState();
}

class _FormulaBlockState extends State<_FormulaBlock> with SelectableMixin {
  late final gestureKey = 'formula-${identityHashCode(this)}';
  AppFlowySelectionService? selection;
  bool outside(Offset position) =>
      box == null || !box!.paintBounds.contains(box!.globalToLocal(position));
  @override
  void initState() {
    super.initState();
    selection = widget.controller.editor.service.selectionService;
    selection?.registerGestureInterceptor(
      SelectionGestureInterceptor(
        key: gestureKey,
        canTap: (d) => outside(d.globalPosition),
        canDoubleTap: (d) => outside(d.globalPosition),
        canPanStart: (d) => outside(d.globalPosition),
      ),
    );
  }

  @override
  void dispose() {
    selection?.unregisterGestureInterceptor(gestureKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '数学公式',
    button: true,
    child: InkWell(
      key: ValueKey('smart-document.formula.${widget.node.id}'),
      onTap: () => showDocumentFormulaEditor(
        context,
        widget.controller,
        reference: DocumentBlockReference(
          objectId: widget.controller.objectId,
          blockId: widget.node.id,
        ),
      ),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.all(12),
        alignment: Alignment.center,
        child: DocumentFormulaRenderer(
          widget.node.attributes['formula'] as String,
        ),
      ),
    ),
  );
  RenderBox? get box => context.findRenderObject() as RenderBox?;
  @override
  Position start() => Position(path: widget.node.path);
  @override
  Position end() => Position(path: widget.node.path, offset: 1);
  @override
  Position getPositionInOffset(Offset offset) => end();
  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: widget.node.path, startOffset: 0, endOffset: 1);
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
