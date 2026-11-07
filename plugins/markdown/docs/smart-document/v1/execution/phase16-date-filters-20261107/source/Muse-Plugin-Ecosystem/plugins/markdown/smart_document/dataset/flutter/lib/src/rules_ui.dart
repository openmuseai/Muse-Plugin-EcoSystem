import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'controller.dart';
import 'projection.dart';

Future<void> showDatasetRulesEditor(
  BuildContext context,
  DatasetController c,
  DatasetViewProjection view, {
  bool sortTab = false,
}) => showDialog<void>(
  context: context,
  builder: (_) => _RulesEditor(controller: c, view: view, sortTab: sortTab),
);

class _RulesEditor extends StatefulWidget {
  const _RulesEditor({
    required this.controller,
    required this.view,
    required this.sortTab,
  });
  final DatasetController controller;
  final DatasetViewProjection view;
  final bool sortTab;
  @override
  State<_RulesEditor> createState() => _RulesEditorState();
}

class _RulesEditorState extends State<_RulesEditor> {
  late final List<Map<String, dynamic>> filters = _copy(widget.view.filters),
      sorts = _copy(widget.view.sorts);
  late bool sorting = widget.sortTab;
  bool busy = false;
  String? error;
  List<DatasetColumn> get columns =>
      widget.view.columns.where((f) => f.editable).toList();
  List<DatasetColumn> get filterColumns => columns;
  static List<Map<String, dynamic>> _copy(List<Map<String, dynamic>> value) =>
      (jsonDecode(jsonEncode(value)) as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
  Map<String, dynamic> leaf(DatasetColumn f) => {
    'id': const Uuid().v4(),
    'filter_type': 2,
    'field_id': f.id,
    'ty': f.storageType,
    'condition': f.isChoice ? 4 : 0,
    'content': f.storageType == 2
        ? '{"start":null,"end":null,"timestamp":null}'
        : '',
  };
  Map<String, dynamic> group() => {
    'id': const Uuid().v4(),
    'filter_type': 0,
    'children': <Map<String, dynamic>>[],
  };
  Map<int, String> conditions(DatasetColumn f) => switch (f.storageType) {
    0 || 6 => {
      0: '等于',
      1: '不等于',
      2: '包含',
      3: '不包含',
      4: '开头是',
      5: '结尾是',
      6: '为空',
      7: '不为空',
    },
    1 => {
      0: '等于',
      1: '不等于',
      2: '大于',
      3: '小于',
      4: '大于等于',
      5: '小于等于',
      6: '为空',
      7: '不为空',
    },
    2 => {
      0: '开始日期为',
      1: '开始日期早于',
      2: '开始日期晚于',
      3: '开始日期不晚于',
      4: '开始日期不早于',
      5: '开始日期介于',
      6: '开始日期为空',
      7: '开始日期不为空',
      8: '结束日期为',
      9: '结束日期早于',
      10: '结束日期晚于',
      11: '结束日期不晚于',
      12: '结束日期不早于',
      13: '结束日期介于',
      14: '结束日期为空',
      15: '结束日期不为空',
    },
    5 => {0: '已勾选', 1: '未勾选'},
    _ => {0: '属于', 1: '不属于', 2: '包含任一选项', 3: '不含任一选项', 4: '为空', 5: '不为空'},
  };
  Future<void> apply() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.configureViewRules(
        widget.view,
        filters: filters,
        sorts: sorts,
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = e.toString().contains('VIEW_RULES_CHANGED')
              ? '视图规则或字段已被修改，请取消后重新打开'
              : '条件未应用，请检查日期、数字、选项或保存状态';
        });
    }
  }

  Widget fieldPicker(
    String value,
    void Function(DatasetColumn) changed, {
    bool forFilter = false,
  }) => DropdownButtonFormField<String>(
    key: ValueKey('rule-field-$value'),
    initialValue: value,
    isExpanded: true,
    decoration: const InputDecoration(labelText: '字段', isDense: true),
    items: [
      for (final f in forFilter ? filterColumns : columns)
        DropdownMenuItem(
          value: f.id,
          child: Text(f.name, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: busy
        ? null
        : (id) =>
              setState(() => changed(columns.firstWhere((f) => f.id == id))),
  );
  Widget filterNode(Map<String, dynamic> node, VoidCallback remove, int depth) {
    final id = node['id'] as String;
    final grouped = node['filter_type'] == 0 || node['filter_type'] == 1;
    final column = grouped
        ? null
        : columns.firstWhere((f) => f.id == node['field_id']);
    final children = grouped ? (node['children'] as List) : null;
    return Container(
      key: ValueKey('dataset.rule.$id'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  grouped ? '条件组' : '筛选条件',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              IconButton(
                tooltip: '删除条件',
                onPressed: busy ? null : () => setState(remove),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (grouped) ...[
            DropdownButtonFormField<int>(
              initialValue: node['filter_type'] as int,
              decoration: const InputDecoration(
                labelText: '组合方式',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 0, child: Text('满足全部条件 · AND')),
                DropdownMenuItem(value: 1, child: Text('满足任一条件 · OR')),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() => node['filter_type'] = v),
            ),
            for (final child in children!)
              filterNode(
                child as Map<String, dynamic>,
                () => children.remove(child),
                depth + 1,
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: busy || filterColumns.isEmpty
                      ? null
                      : () => setState(
                          () => children.add(leaf(filterColumns.first)),
                        ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加条件'),
                ),
                if (depth < 4)
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => children.add(group())),
                    child: const Text('添加条件组'),
                  ),
              ],
            ),
          ] else ...[
            fieldPicker(column!.id, (f) {
              node
                ..['field_id'] = f.id
                ..['ty'] = f.storageType
                ..['condition'] = f.isChoice ? 4 : 0
                ..['content'] = f.storageType == 2
                    ? '{"start":null,"end":null,"timestamp":null}'
                    : '';
            }, forFilter: true),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('rule-condition-$id-${column.id}'),
              initialValue: node['condition'] as int,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '条件', isDense: true),
              items: [
                for (final e in conditions(column).entries)
                  DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: busy
                  ? null
                  : (v) => setState(() => node['condition'] = v),
            ),
            if (column.storageType == 2)
              ...dateInputs(node, column)
            else if (column.isChoice && (node['condition'] as int) < 4) ...[
              const SizedBox(height: 8),
              for (final option in column.options)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(option.name),
                  value: (node['content'] as String)
                      .split(',')
                      .contains(option.id),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          final ids = (node['content'] as String)
                              .split(',')
                              .where((s) => s.isNotEmpty)
                              .toSet();
                          if (v == true) {
                            ids.add(option.id);
                          } else {
                            ids.remove(option.id);
                          }
                          node['content'] = ids.join(',');
                        }),
                ),
            ] else if (column.storageType != 5 &&
                (node['condition'] as int) < 6) ...[
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('dataset.rule-content.$id-${column.id}'),
                initialValue: node['content'] as String,
                enabled: !busy,
                maxLength: 4096,
                decoration: InputDecoration(
                  labelText: column.storageType == 1 ? '数值（精确小数）' : '内容',
                  helperText: column.storageType == 1 ? null : '忽略大小写；空内容不限制记录',
                ),
                onChanged: (v) => node['content'] = v,
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<Widget> dateInputs(Map<String, dynamic> node, DatasetColumn column) {
    final condition = (node['condition'] as int) % 8;
    final source = node['content'] is Map
        ? node['content'] as Map
        : widget.view.dateFilterInputs[node['id']] as Map? ?? const {};
    return [
      const SizedBox(height: 8),
      Text('按字段时区 ${column.timezone} 比较日历日期；未填日期不限制记录。'),
      if (condition < 6)
        for (final key in condition == 5 ? ['start', 'end'] : ['timestamp'])
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _RuleDateInput(
              key: ValueKey(
                'dataset.rule-date.${node['id']}-$key-${column.id}',
              ),
              initialValue: source[key] as String? ?? '',
              enabled: !busy,
              label: key == 'start'
                  ? '起始日期'
                  : key == 'end'
                  ? '截止日期'
                  : '日期',
              onChanged: (v) {
                final draft = Map<String, dynamic>.from(
                  node['content'] is Map ? node['content'] as Map : source,
                );
                draft[key] = v;
                node['content'] = draft;
              },
            ),
          ),
    ];
  }

  Widget sortNode(Map<String, dynamic> node, int index) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('第 ${index + 1} 优先级')),
            IconButton(
              tooltip: '提高排序优先级',
              onPressed: busy || index == 0
                  ? null
                  : () => setState(() {
                      sorts.removeAt(index);
                      sorts.insert(index - 1, node);
                    }),
              icon: const Icon(Icons.arrow_upward, size: 18),
            ),
            IconButton(
              tooltip: '降低排序优先级',
              onPressed: busy || index == sorts.length - 1
                  ? null
                  : () => setState(() {
                      sorts.removeAt(index);
                      sorts.insert(index + 1, node);
                    }),
              icon: const Icon(Icons.arrow_downward, size: 18),
            ),
            IconButton(
              tooltip: '删除排序',
              onPressed: busy ? null : () => setState(() => sorts.remove(node)),
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
        fieldPicker(node['field_id'] as String, (f) => node['field_id'] = f.id),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: ValueKey('rule-direction-${node['id']}'),
          initialValue: node['condition'] as int,
          decoration: const InputDecoration(labelText: '顺序', isDense: true),
          items: const [
            DropdownMenuItem(value: 0, child: Text('升序')),
            DropdownMenuItem(value: 1, child: Text('降序')),
          ],
          onChanged: busy ? null : (v) => setState(() => node['condition'] = v),
        ),
        const Divider(height: 24),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const Text('视图设置'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('筛选'),
                    icon: Icon(Icons.filter_alt_outlined),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('排序'),
                    icon: Icon(Icons.sort),
                  ),
                ],
                selected: {sorting},
                onSelectionChanged: busy
                    ? null
                    : (v) => setState(() => sorting = v.single),
              ),
              const SizedBox(height: 12),
              const Text('当前视图的设置会同步给协作者，不会删除原始记录。'),
              if (!sorting) ...[
                if (filters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('显示全部记录'),
                  ),
                for (final node in filters)
                  filterNode(node, () => filters.remove(node), 0),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('dataset.rules-add-filter'),
                      onPressed: busy || filterColumns.isEmpty
                          ? null
                          : () => setState(
                              () => filters.add(leaf(filterColumns.first)),
                            ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加条件'),
                    ),
                    TextButton(
                      key: const ValueKey('dataset.rules-add-group'),
                      onPressed: busy
                          ? null
                          : () => setState(() => filters.add(group())),
                      child: const Text('添加条件组'),
                    ),
                  ],
                ),
                if (filters.length > 1) const Text('顶层条件按“全部满足”组合。'),
                const Text(
                  '筛选支持文本、数字、日期、选项、复选框和链接。',
                  style: TextStyle(fontSize: 12),
                ),
              ] else ...[
                const Text(
                  '从上到下依次比较；空值置后，相同值保留手动顺序。',
                  style: TextStyle(fontSize: 12),
                ),
                for (var i = 0; i < sorts.length; i++) sortNode(sorts[i], i),
                TextButton.icon(
                  key: const ValueKey('dataset.rules-add-sort'),
                  onPressed:
                      busy ||
                          columns.every(
                            (f) => sorts.any((s) => s['field_id'] == f.id),
                          )
                      ? null
                      : () => setState(() {
                          final f = columns.firstWhere(
                            (f) => !sorts.any((s) => s['field_id'] == f.id),
                          );
                          sorts.add({
                            'id': const Uuid().v4(),
                            'field_id': f.id,
                            'condition': 0,
                          });
                        }),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('添加排序'),
                ),
              ],
              if (error != null)
                Text(
                  error!,
                  key: const ValueKey('dataset.rules-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                  filters.clear();
                  sorts.clear();
                }),
          child: const Text('清除设置'),
        ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('dataset.rules-apply'),
          onPressed: busy ? null : apply,
          child: Text(busy ? '正在应用…' : '应用'),
        ),
      ],
    ),
  );
}

class _RuleDateInput extends StatefulWidget {
  const _RuleDateInput({
    super.key,
    required this.initialValue,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });
  final String initialValue, label;
  final bool enabled;
  final ValueChanged<String> onChanged;
  @override
  State<_RuleDateInput> createState() => _RuleDateInputState();
}

class _RuleDateInputState extends State<_RuleDateInput> {
  late final input = TextEditingController(text: widget.initialValue);
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final parsed = DateTime.tryParse(input.text);
    final day = await showDatePicker(
      context: context,
      initialDate: parsed != null && parsed.year >= 1 && parsed.year <= 9999
          ? parsed
          : DateTime(2026, 1, 1),
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (day == null || !mounted) return;
    final value =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    input.text = value;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: input,
    enabled: widget.enabled,
    maxLength: 10,
    keyboardType: TextInputType.datetime,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: 'YYYY-MM-DD',
      suffixIcon: IconButton(
        tooltip: '选择筛选日期',
        onPressed: widget.enabled ? pick : null,
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    ),
  );
}
