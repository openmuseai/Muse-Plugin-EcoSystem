import 'dart:convert';
import 'package:flutter/material.dart';
import 'controller.dart';
import 'projection.dart';
import 'choice_ui.dart';
import 'date_ui.dart';

String displayCell(Object? value) => value == null
    ? ''
    : value is String
    ? value
    : value is Map || value is List
    ? jsonEncode(value)
    : '$value';
Future<void> showDatasetCellEditor(
  BuildContext context,
  DatasetController controller,
  DatasetRow row,
  DatasetColumn column,
) => column.isChoice
    ? showDatasetChoiceEditor(context, controller, row, column)
    : column.semanticType == 'date'
    ? showDatasetDateEditor(context, controller, row, column)
    : showDialog<void>(
        context: context,
        builder: (_) =>
            _CellEditor(controller: controller, row: row, column: column),
      );
Future<void> showDatasetFieldEditor(
  BuildContext context,
  DatasetController controller,
  String semanticType, {
  DatasetColumn? field,
}) => showDialog<void>(
  context: context,
  builder: (_) => _FieldEditor(
    controller: controller,
    semanticType: semanticType,
    field: field,
  ),
);

class _CellEditor extends StatefulWidget {
  const _CellEditor({
    required this.controller,
    required this.row,
    required this.column,
  });
  final DatasetController controller;
  final DatasetRow row;
  final DatasetColumn column;
  @override
  State<_CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<_CellEditor> {
  late final input = TextEditingController(
    text: displayCell(widget.row.cells[widget.column.id]!.value),
  );
  bool busy = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => busy = true);
    try {
      await widget.controller.setCell(
        widget.row,
        widget.column,
        input.text,
        expectedHash: widget.row.cells[widget.column.id]!.hash,
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (!mounted) return;
      // The domain command succeeded if only the checkpoint failed. Do not replay
      // it (especially field creation); keep the visible draft and retry saving.
      if (widget.controller.persistenceFailure != null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        busy = false;
        error = e.toString().contains('CELL_CHANGED')
            ? '内容已被修改，请取消后重新编辑'
            : '输入无效或操作未提交，请检查后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      key: const ValueKey('dataset.cell-dialog'),
      title: Text(widget.column.name),
      content: SizedBox(
        width: 360,
        child: TextField(
          key: const ValueKey('dataset.cell-input'),
          controller: input,
          enabled: !busy,
          autofocus: true,
          keyboardType: widget.column.semanticType == 'number'
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : widget.column.semanticType == 'url'
              ? TextInputType.url
              : TextInputType.multiline,
          minLines: 1,
          maxLines: widget.column.semanticType == 'text' ? 5 : 1,
          decoration: InputDecoration(
            labelText: widget.column.name,
            errorText: error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('dataset.cell-apply'),
          onPressed: busy ? null : _apply,
          child: const Text('应用'),
        ),
      ],
    ),
  );
}

class _FieldEditor extends StatefulWidget {
  const _FieldEditor({
    required this.controller,
    required this.semanticType,
    this.field,
  });
  final DatasetController controller;
  final String semanticType;
  final DatasetColumn? field;
  @override
  State<_FieldEditor> createState() => _FieldEditorState();
}

class _FieldEditorState extends State<_FieldEditor> {
  late final input = TextEditingController(text: widget.field?.name ?? '');
  final optionInput = TextEditingController(text: '待处理\n进行中\n已完成');
  late final timezoneInput = TextEditingController(
    text: widget.field?.timezone ?? 'Etc/UTC',
  );
  bool get creatingChoice =>
      widget.field == null &&
      {'singleSelect', 'multiSelect'}.contains(widget.semanticType);
  bool busy = false;
  String? error;
  @override
  void dispose() {
    input.dispose();
    optionInput.dispose();
    timezoneInput.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => busy = true);
    try {
      if (widget.field == null) {
        final names = creatingChoice
            ? optionInput.text
                  .split('\n')
                  .map((v) => v.trim())
                  .where((v) => v.isNotEmpty)
                  .toList()
            : <String>[];
        if (creatingChoice && names.isEmpty) {
          setState(() {
            busy = false;
            error = '请至少填写一个选项';
          });
          return;
        }
        await widget.controller.createField(
          input.text,
          widget.semanticType,
          timezone: widget.semanticType == 'date'
              ? timezoneInput.text.trim()
              : null,
          options: [
            for (var i = 0; i < names.length; i++)
              DatasetOptionDraft(name: names[i], color: i % 9),
          ],
        );
      } else if (widget.semanticType == 'date') {
        await widget.controller.configureDateField(
          widget.field!,
          input.text,
          timezoneInput.text.trim(),
        );
      } else {
        await widget.controller.renameField(widget.field!, input.text);
      }
      if (mounted) Navigator.pop(context);
    } on Object {
      if (!mounted) return;
      if (widget.controller.persistenceFailure != null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        busy = false;
        error = '字段已变化或名称无效，请重新检查';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      key: const ValueKey('dataset.field-dialog'),
      title: Text(widget.field == null ? '新增字段' : '重命名字段'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const ValueKey('dataset.field-name'),
                controller: input,
                enabled: !busy,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '字段名称',
                  errorText: error,
                ),
              ),
              if (creatingChoice) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('dataset.field-options'),
                  controller: optionInput,
                  enabled: !busy,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '选项（每行一个）',
                    helperText: '最多 64 项，名称不能重复',
                  ),
                ),
              ],
              if (widget.semanticType == 'date') ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('dataset.field-timezone'),
                  controller: timezoneInput,
                  enabled: !busy,
                  decoration: const InputDecoration(
                    labelText: '字段时区',
                    helperText: 'IANA 时区，例如 Asia/Shanghai；所有协作者共用',
                  ),
                ),
                if (widget.field != null) const Text('修改时区会改变显示时间，保留原时刻。'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('dataset.field-apply'),
          onPressed: busy ? null : _apply,
          child: const Text('应用'),
        ),
      ],
    ),
  );
}
