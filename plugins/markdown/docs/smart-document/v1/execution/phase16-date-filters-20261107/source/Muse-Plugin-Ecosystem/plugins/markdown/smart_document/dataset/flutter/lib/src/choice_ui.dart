import 'package:flutter/material.dart';
import 'controller.dart';
import 'projection.dart';

Color _color(int value) => const [
  Color(0xff7756ad),
  Color(0xffb94e8b),
  Color(0xffd5809b),
  Color(0xffc66e26),
  Color(0xffb29118),
  Color(0xff729329),
  Color(0xff27894e),
  Color(0xff238c91),
  Color(0xff3574bf),
][value.clamp(0, 8)];

/// Shared native/web choice projection. Only stable IDs reach domain commands;
/// labels, palette and menus are presentation, not another cell data model.
final class DatasetChoiceCell extends StatelessWidget {
  const DatasetChoiceCell({
    super.key,
    required this.column,
    required this.cell,
  });
  final DatasetColumn column;
  final DatasetCell cell;
  @override
  Widget build(BuildContext context) {
    if (!column.editable) return const Text('字段配置暂不可编辑');
    if (cell.unresolvedOptions) return const Text('包含无效选项，请重新选择');
    final choices = [
      for (final id in cell.selectedOptionIds)
        ...column.options.where((v) => v.id == id),
    ];
    return Row(
      children: [
        for (final option in choices.take(2))
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: option.name,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _color(option.color).withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    option.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        if (choices.length > 2) Text('+${choices.length - 2}'),
      ],
    );
  }
}

Future<void> showDatasetChoiceEditor(
  BuildContext context,
  DatasetController controller,
  DatasetRow row,
  DatasetColumn column,
) => showDialog<void>(
  context: context,
  builder: (_) =>
      _ChoiceEditor(controller: controller, row: row, column: column),
);

class _ChoiceEditor extends StatefulWidget {
  const _ChoiceEditor({
    required this.controller,
    required this.row,
    required this.column,
  });
  final DatasetController controller;
  final DatasetRow row;
  final DatasetColumn column;
  @override
  State<_ChoiceEditor> createState() => _ChoiceEditorState();
}

class _ChoiceEditorState extends State<_ChoiceEditor> {
  late final selected = List<String>.of(
    widget.row.cells[widget.column.id]!.selectedOptionIds,
  );
  bool busy = false;
  String? error;
  bool get multiple => widget.column.semanticType == 'multiSelect';
  void _toggle(String id) => setState(() {
    if (multiple) {
      if (selected.contains(id)) {
        selected.removeWhere((v) => v == id);
      } else {
        selected.add(id);
      }
    } else {
      selected
        ..clear()
        ..add(id);
    }
  });
  Future<void> _apply() async {
    setState(() => busy = true);
    try {
      await widget.controller.setCell(
        widget.row,
        widget.column,
        List<String>.of(selected),
        expectedHash: widget.row.cells[widget.column.id]!.hash,
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (!mounted) return;
      if (widget.controller.persistenceFailure != null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        busy = false;
        error =
            e.toString().contains('CELL_CHANGED') ||
                e.toString().contains('FIELD_CHANGED')
            ? '内容或选项已变化，请取消后重新打开'
            : '选项无效，请重新选择';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unknown = selected
        .where((id) => !widget.column.options.any((v) => v.id == id))
        .toSet()
        .toList();
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        key: const ValueKey('dataset.choice-dialog'),
        title: Text(widget.column.name),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (unknown.isNotEmpty)
                Wrap(
                  spacing: 4,
                  children: [
                    for (final id in unknown.take(8))
                      InputChip(
                        label: const Text('已移除选项'),
                        onDeleted: busy
                            ? null
                            : () => setState(
                                () => selected.removeWhere((v) => v == id),
                              ),
                      ),
                  ],
                ),
              if (unknown.length > 8)
                Text('还有 ${unknown.length - 8} 项无效选项，可清空后重新选择'),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .4,
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final option in widget.column.options)
                      Semantics(
                        checked: selected.contains(option.id),
                        inMutuallyExclusiveGroup: !multiple,
                        child: ListTile(
                          key: ValueKey('dataset.choice-option.${option.id}'),
                          selected: selected.contains(option.id),
                          minVerticalPadding: 8,
                          leading: Icon(
                            multiple
                                ? (selected.contains(option.id)
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank)
                                : (selected.contains(option.id)
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked),
                            color: _color(option.color),
                          ),
                          title: Text(option.name),
                          onTap: busy ? null : () => _toggle(option.id),
                        ),
                      ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('dataset.choice-clear'),
            onPressed: busy ? null : () => setState(selected.clear),
            child: const Text('清空'),
          ),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('dataset.choice-apply'),
            onPressed: busy ? null : _apply,
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }
}
