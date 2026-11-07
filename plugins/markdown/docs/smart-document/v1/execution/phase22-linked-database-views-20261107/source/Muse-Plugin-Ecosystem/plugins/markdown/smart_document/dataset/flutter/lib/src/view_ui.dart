import 'package:flutter/material.dart';
import 'controller.dart';
import 'projection.dart';

Future<String?> showDatasetViewEditor(
  BuildContext context,
  DatasetController controller, {
  DatasetViewProjection? view,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ViewEditor(controller: controller, view: view),
);

class _ViewEditor extends StatefulWidget {
  const _ViewEditor({required this.controller, this.view});
  final DatasetController controller;
  final DatasetViewProjection? view;
  @override
  State<_ViewEditor> createState() => _ViewEditorState();
}

class _ViewEditorState extends State<_ViewEditor> {
  late final input = TextEditingController(text: widget.view?.name ?? '表格视图');
  bool busy = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> apply() async {
    if (widget.view != null && input.text == widget.view!.name) {
      Navigator.pop(context, widget.view!.id);
      return;
    }
    setState(() => busy = true);
    try {
      final view = widget.view;
      final String id;
      if (view == null) {
        id = await widget.controller.createGridView(input.text);
      } else {
        await widget.controller.renameView(view, input.text);
        id = view.id;
      }
      if (mounted) Navigator.pop(context, id);
    } on Object {
      if (!mounted) return;
      if (widget.controller.persistenceFailure != null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        busy = false;
        error = '视图已变化或名称无效，请重新检查';
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        key: const ValueKey('dataset.view-dialog'),
        title: Text(widget.view == null ? '新增表格视图' : '视图设置'),
        content: SizedBox(
          width: 360,
          child: TextField(
            key: const ValueKey('dataset.view-name'),
            controller: input,
            autofocus: true,
            enabled: !busy && widget.controller.canWrite,
            decoration: InputDecoration(labelText: '视图名称', errorText: error),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('dataset.view-apply'),
            onPressed: busy || !widget.controller.canWrite ? null : apply,
            child: const Text('应用'),
          ),
        ],
      ),
    ),
  );
}
