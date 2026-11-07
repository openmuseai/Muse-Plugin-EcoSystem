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
  int layout = 0;
  late final fields = <String, DatasetColumn>{
    for (final view in widget.controller.views)
      for (final f in view.columns)
        if (f.semanticType == 'singleSelect' && f.editable) f.id: f,
  };
  late String? fieldId = fields.keys.firstOrNull;
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
        if (layout == 1) {
          final field = fields[fieldId];
          if (field == null) throw StateError('分组字段不可用');
          id = await widget.controller.createBoardView(input.text, field);
        } else {
          id = await widget.controller.createGridView(input.text);
        }
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

  Widget _groupField() {
    if (fields.isEmpty) return const Text('请先新增单选字段，再以该字段创建看板');
    return DropdownButtonFormField<String>(
      key: const ValueKey('dataset.board-field'),
      initialValue: fieldId,
      decoration: const InputDecoration(labelText: '按单选字段分组'),
      items: [
        for (final field in fields.values)
          DropdownMenuItem(value: field.id, child: Text(field.name)),
      ],
      onChanged: busy ? null : (v) => setState(() => fieldId = v),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        key: const ValueKey('dataset.view-dialog'),
        title: Text(widget.view == null ? '新增视图' : '视图设置'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('dataset.view-name'),
                controller: input,
                autofocus: true,
                enabled: !busy && widget.controller.canWrite,
                decoration: InputDecoration(
                  labelText: '视图名称',
                  errorText: error,
                ),
              ),
              if (widget.view == null) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const ValueKey('dataset.view-layout'),
                  initialValue: layout,
                  decoration: const InputDecoration(labelText: '视图类型'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('表格')),
                    DropdownMenuItem(value: 1, child: Text('看板')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => layout = v ?? 0),
                ),
                if (layout == 1) ...[const SizedBox(height: 12), _groupField()],
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('dataset.view-apply'),
            onPressed:
                busy ||
                    !widget.controller.canWrite ||
                    (widget.view == null && layout == 1 && fieldId == null)
                ? null
                : apply,
            child: const Text('应用'),
          ),
        ],
      ),
    ),
  );
}
