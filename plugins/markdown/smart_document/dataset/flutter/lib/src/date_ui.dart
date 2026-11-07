import 'package:flutter/material.dart';
import 'controller.dart';
import 'projection.dart';

String displayDateCell(DatasetCell cell) {
  if (cell.unresolvedDate) return '日期格式暂不支持，原值保留';
  final value = cell.value;
  if (value is! Map || value['start'] == null) return '';
  String text(Object? v) => (v as String).replaceFirst('T', ' ');
  return '${text(value['start'])}${value['isRange'] == true ? ' → ${value['end'] == null ? '未设置' : text(value['end'])}' : ''}';
}

Future<void> showDatasetDateEditor(
  BuildContext context,
  DatasetController c,
  DatasetRow row,
  DatasetColumn column,
) => showDialog<void>(
  context: context,
  builder: (_) => _DateEditor(controller: c, row: row, column: column),
);

class _DateEditor extends StatefulWidget {
  const _DateEditor({
    required this.controller,
    required this.row,
    required this.column,
  });
  final DatasetController controller;
  final DatasetRow row;
  final DatasetColumn column;
  @override
  State<_DateEditor> createState() => _DateEditorState();
}

class _DateEditorState extends State<_DateEditor> {
  late final Map value =
      widget.row.cells[widget.column.id]!.value as Map? ?? {};
  late final start = TextEditingController(
    text: value['start'] as String? ?? '',
  );
  late final end = TextEditingController(text: value['end'] as String? ?? '');
  late bool timed = value['includeTime'] == true,
      range = value['isRange'] == true;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    start.dispose();
    end.dispose();
    super.dispose();
  }

  void _timed(bool value) {
    setState(() {
      timed = value;
      for (final input in [start, end]) {
        if (input.text.length < 10) continue;
        input.text = value
            ? '${input.text.substring(0, 10)}T00:00:00'
            : input.text.substring(0, 10);
      }
    });
  }

  Future<void> _pick(TextEditingController input) async {
    // DatePicker's DateTime is used only as a civil calendar tuple. Never call
    // toUtc/local/epoch here; the Rust boundary resolves the explicit field zone.
    final old = DateTime.tryParse(
      input.text.length >= 10 ? input.text.substring(0, 10) : '',
    );
    final date = await showDatePicker(
      context: context,
      initialDate: old != null && old.year >= 1 && old.year <= 9999
          ? old
          : null,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    String pad(int v) => '$v'.padLeft(2, '0');
    final civil =
        '${'${date.year}'.padLeft(4, '0')}-${pad(date.month)}-${pad(date.day)}';
    if (input.text.length >= 10 && input.text.substring(0, 10) == civil) return;
    final time =
        RegExp(
          r'[T ](\d{2}:\d{2}(?::\d{2})?)',
        ).firstMatch(input.text)?.group(1) ??
        '00:00:00';
    // A changed civil date may have a different DST offset. Resolve again in
    // the field zone instead of copying a now-stale offset onto the new date.
    input.text = '$civil${timed ? 'T$time' : ''}';
  }

  Future<void> _pickTime(TextEditingController input) async {
    final parts = RegExp(r'[T ](\d{2}):(\d{2})').firstMatch(input.text);
    final hour = int.tryParse(parts?.group(1) ?? '') ?? 0;
    final minute = int.tryParse(parts?.group(2) ?? '') ?? 0;
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: hour < 24 ? hour : 0,
        minute: minute < 60 ? minute : 0,
      ),
    );
    if (chosen == null || !mounted) return;
    final date = input.text.length >= 10 ? input.text.substring(0, 10) : '';
    if (date.isEmpty) {
      setState(() => error = '请先选择日期');
      return;
    }
    String pad(int v) => '$v'.padLeft(2, '0');
    input.text = '${date}T${pad(chosen.hour)}:${pad(chosen.minute)}:00';
  }

  Future<void> _apply({bool clear = false}) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.setCell(
        widget.row,
        widget.column,
        clear
            ? null
            : {
                'start': start.text.trim(),
                'end': range && end.text.trim().isNotEmpty
                    ? end.text.trim()
                    : null,
                'includeTime': timed,
                'isRange': range,
              },
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
        final code = e.toString();
        error = code.contains('CELL_CHANGED')
            ? '内容已被修改，草稿保留，请取消后重新编辑'
            : code.contains('FIELD_CHANGED')
            ? '字段或时区已变化，草稿保留，请取消后重新编辑'
            : code.contains('DATE_LOCAL_TIME_GAP')
            ? '该时间在此时区不存在，请重新选择'
            : code.contains('DATE_LOCAL_TIME_AMBIGUOUS')
            ? '该时间出现两次，请填写含正确偏移量的完整时间'
            : code.contains('DATE_OFFSET_MISMATCH')
            ? '时间偏移量与字段时区不一致'
            : code.contains('DATE_RANGE_REVERSED')
            ? '结束日期不能早于开始日期'
            : '日期无效，请检查格式；支持到秒，不会自动改为今天';
      });
    }
  }

  Widget _input(TextEditingController input, String key, String label) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: ValueKey('dataset.date-$key'),
            controller: input,
            enabled: !busy,
            decoration: InputDecoration(
              labelText: label,
              hintText: timed ? '2026-11-06T09:30:00' : '2026-11-06',
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              Tooltip(
                message: '选择${key == 'start' ? '开始' : '结束'}日期',
                child: TextButton.icon(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: busy ? null : () => _pick(input),
                  icon: const Icon(Icons.calendar_month_outlined, size: 20),
                  label: const Text('选择日期'),
                ),
              ),
              if (timed)
                Tooltip(
                  message: '选择${key == 'start' ? '开始' : '结束'}时间',
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    onPressed: busy ? null : () => _pickTime(input),
                    icon: const Icon(Icons.schedule, size: 20),
                    label: const Text('选择时间'),
                  ),
                ),
            ],
          ),
        ],
      );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      key: const ValueKey('dataset.date-dialog'),
      title: Text(widget.column.name),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('时区：${widget.column.timezone}'),
              ),
              _input(start, 'start', '开始日期'),
              SwitchListTile(
                key: const ValueKey('dataset.date-time'),
                title: const Text('包含时间'),
                value: timed,
                onChanged: busy ? null : _timed,
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                key: const ValueKey('dataset.date-range'),
                title: const Text('结束日期'),
                value: range,
                onChanged: busy ? null : (v) => setState(() => range = v),
                contentPadding: EdgeInsets.zero,
              ),
              if (range) _input(end, 'end', '结束日期（可留空）'),
              if (timed) const Text('使用字段时区。夏令时重复时刻需附偏移量，如 -04:00。'),
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
      ),
      actions: [
        TextButton(
          key: const ValueKey('dataset.date-clear'),
          onPressed: busy ? null : () => _apply(clear: true),
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('dataset.date-apply'),
          onPressed: busy ? null : _apply,
          child: const Text('应用'),
        ),
      ],
    ),
  );
}
