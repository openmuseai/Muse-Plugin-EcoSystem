import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'controller.dart';
import 'projection.dart';
import 'dialogs.dart';
import 'choice_ui.dart';
import 'date_ui.dart';
import 'realtime_session.dart';
import 'collaborators_view.dart';
import 'rules_ui.dart';
import 'record_ui.dart';
import 'view_ui.dart';
import 'board_ui.dart';

/// Shared independent/embedded surface. The owner supplies a bounded domain
/// session; no private Host services or document editor state are accessed.
final class DatasetSurface extends StatefulWidget {
  const DatasetSurface({
    super.key,
    required this.controller,
    required this.title,
    this.viewId,
    this.allowEditing = true,
    this.embedded = false,
    this.realtime,
  });
  final DatasetController controller;
  final String title;
  final String? viewId;
  final bool allowEditing, embedded;
  final DatasetRealtimeSession? realtime;
  @override
  State<DatasetSurface> createState() => _DatasetSurfaceState();
}

class _DatasetSurfaceState extends State<DatasetSurface> {
  final _historyFocus = FocusNode(debugLabel: 'Dataset history');
  DatasetController get c => widget.controller;
  String? selected;
  bool busy = false;
  void _selectView(String? id) {
    if (selected == id) return;
    widget.realtime?.clearSelection();
    setState(() => selected = id);
  }

  @override
  void initState() {
    super.initState();
    selected = widget.viewId ?? c.views.firstOrNull?.id;
  }

  @override
  void didUpdateWidget(covariant DatasetSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, c) ||
        oldWidget.viewId != widget.viewId) {
      selected = widget.viewId ?? c.views.firstOrNull?.id;
    }
  }

  @override
  void dispose() {
    _historyFocus.dispose();
    super.dispose();
  }

  Future<void> _history({bool redo = false}) async {
    final applied = await c.history(redo: redo);
    if (mounted && !applied) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这条修改已被协作者覆盖，当前内容已保留')));
    }
  }

  void _keyboardHistory({bool redo = false}) {
    final id = selected ?? widget.viewId;
    final view = id == null
        ? c.views.firstOrNull
        : c.views.where((v) => v.id == id).firstOrNull;
    if (!widget.allowEditing ||
        !c.canWrite ||
        busy ||
        (view != null && !view.supportedLayout) ||
        view?.rulesReady == false ||
        (redo ? !c.canRedo : !c.canUndo))
      return;
    unawaited(_run(() => _history(redo: redo)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } on Object {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              c.persistenceFailure != null
                  ? '修改已留在当前会话，本机保存未完成，请重试保存'
                  : '操作未完成，请检查内容或保存状态',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _status() => c.unavailableRows.isNotEmpty
      ? '协作记录暂不可用 · 本机副本保留'
      : switch ((c.saveState, c.syncState)) {
          (DatasetSaveState.failed, _) => '本机保存失败，请保留页面并重试',
          (DatasetSaveState.dirty, _) => '正在保存到本机…',
          (_, DatasetSyncState.accepted) => '已保存到本机 · 协作服务已接收',
          (_, DatasetSyncState.exchanging) => '已保存到本机 · 正在同步',
          (_, DatasetSyncState.pending) =>
            widget.realtime?.connected == true
                ? '已保存到本机 · 实时连接正常，等待接收确认'
                : '已保存到本机 · 待同步',
          (_, DatasetSyncState.forbidden) => '无权访问云端数据，当前会话只读',
          (_, DatasetSyncState.removed) => '云端数据已移除 · 本机副本保留',
          (_, DatasetSyncState.unavailable) =>
            widget.realtime?.connected == true
                ? '实时连接正常 · 接收确认暂不可用 · 本机修改保留'
                : '协作暂不可用 · 本机修改保留',
          _ => '已保存到本机 · 本机数据集',
        };
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _historyFocus.requestFocus(),
    child: CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
            _keyboardHistory(),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
            _keyboardHistory(),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          meta: true,
          shift: true,
        ): () =>
            _keyboardHistory(redo: true),
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): () =>
            _keyboardHistory(redo: true),
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
            _keyboardHistory(redo: true),
      },
      child: Focus(
        key: const ValueKey('dataset.history-focus'),
        focusNode: _historyFocus,
        child: _content(context),
      ),
    ),
  );
  Widget _content(BuildContext context) => ListenableBuilder(
    listenable: widget.realtime == null
        ? c
        : Listenable.merge([c, widget.realtime!]),
    builder: (context, _) {
      final views = c.views;
      final id = selected ?? widget.viewId;
      // An explicit missing view must never redirect to unrelated content.
      final view = id == null
          ? views.firstOrNull
          : views.where((v) => v.id == id).firstOrNull;
      final editable =
          widget.allowEditing &&
          c.canWrite &&
          c.persistenceFailure == null &&
          view?.supportedLayout == true &&
          view?.rulesReady != false &&
          !busy;
      final colors = Theme.of(context).colorScheme;
      return ColoredBox(
        color: colors.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.table_chart_outlined, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (widget.realtime != null)
                    DatasetCollaboratorsView(session: widget.realtime!),
                  if (!c.canWrite || !widget.allowEditing) const Text('只读'),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _toolbar(
                view?.layout == 1,
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    if (views.isNotEmpty)
                      DropdownButton<String>(
                        key: const ValueKey('dataset.view-picker'),
                        value: view?.id,
                        hint: const Text('选择视图'),
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final v in views)
                            DropdownMenuItem(
                              value: v.id,
                              child: Text(v.name.isEmpty ? '表格' : v.name),
                            ),
                        ],
                        onChanged: busy || !c.canRead ? null : _selectView,
                      ),
                    IconButton(
                      key: const ValueKey('dataset.add-view'),
                      tooltip: '新增视图',
                      onPressed: widget.allowEditing && c.canWrite && !busy
                          ? () => _run(() async {
                              final id = await showDatasetViewEditor(
                                context,
                                c,
                              );
                              if (mounted && id != null) _selectView(id);
                            })
                          : null,
                      icon: const Icon(Icons.add_chart_outlined, size: 20),
                    ),
                    IconButton(
                      key: const ValueKey('dataset.view-settings'),
                      tooltip: '视图设置',
                      onPressed: editable && view != null
                          ? () => showDatasetViewEditor(context, c, view: view)
                          : null,
                      icon: const Icon(Icons.edit_note, size: 20),
                    ),
                    if (view != null) ...[
                      TextButton.icon(
                        key: const ValueKey('dataset.filters'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                        ),
                        onPressed: editable && view.rulesHash != null
                            ? () => showDatasetRulesEditor(context, c, view)
                            : null,
                        icon: const Icon(Icons.filter_alt_outlined, size: 18),
                        label: Text(view.filters.isEmpty ? '筛选' : '筛选 · 已启用'),
                      ),
                      TextButton.icon(
                        key: const ValueKey('dataset.sorts'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                        ),
                        onPressed: editable && view.rulesHash != null
                            ? () => showDatasetRulesEditor(
                                context,
                                c,
                                view,
                                sortTab: true,
                              )
                            : null,
                        icon: const Icon(Icons.sort, size: 18),
                        label: Text(
                          view.sorts.isEmpty
                              ? '排序'
                              : '排序 · ${view.sorts.length}',
                        ),
                      ),
                    ],
                    IconButton(
                      key: const ValueKey('dataset.undo'),
                      tooltip: '撤销',
                      onPressed:
                          (editable ||
                                  (view == null &&
                                      widget.allowEditing &&
                                      c.canWrite &&
                                      !busy)) &&
                              c.canUndo
                          ? () => _run(() => _history())
                          : null,
                      icon: const Icon(Icons.undo, size: 20),
                    ),
                    IconButton(
                      key: const ValueKey('dataset.redo'),
                      tooltip: '重做',
                      onPressed:
                          (editable ||
                                  (view == null &&
                                      widget.allowEditing &&
                                      c.canWrite &&
                                      !busy)) &&
                              c.canRedo
                          ? () => _run(() => _history(redo: true))
                          : null,
                      icon: const Icon(Icons.redo, size: 20),
                    ),
                    TextButton.icon(
                      key: const ValueKey('dataset.add-row'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      onPressed: editable
                          ? () => _run(() async {
                              final rowId = await c.addRow(viewId: view!.id);
                              if (!mounted) return;
                              final current = c.views
                                  .where((v) => v.id == view.id)
                                  .firstOrNull;
                              if (current != null &&
                                  !current.rows.any((r) => r.id == rowId)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('记录已创建，当前筛选下不可见'),
                                    duration: const Duration(seconds: 10),
                                    action: SnackBarAction(
                                      label: '编辑新记录',
                                      onPressed: () => showDatasetRecordEditor(
                                        context,
                                        c,
                                        view.id,
                                        rowId,
                                      ),
                                    ),
                                  ),
                                );
                              }
                            })
                          : null,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新增记录'),
                    ),
                    PopupMenuButton<String>(
                      key: const ValueKey('dataset.add-field'),
                      tooltip: '新增字段',
                      enabled: editable,
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'text', child: Text('文本')),
                        PopupMenuItem(value: 'number', child: Text('数字')),
                        PopupMenuItem(value: 'date', child: Text('日期')),
                        PopupMenuItem(value: 'checkbox', child: Text('复选框')),
                        PopupMenuItem(value: 'url', child: Text('链接')),
                        PopupMenuItem(value: 'singleSelect', child: Text('单选')),
                        PopupMenuItem(value: 'multiSelect', child: Text('多选')),
                      ],
                      onSelected: (type) =>
                          showDatasetFieldEditor(context, c, type),
                      child: const SizedBox(
                        height: 44,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: Center(widthFactor: 1, child: Text('新增字段')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (c.persistenceFailure != null || c.syncFailure != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(child: Text(_status())),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _run(() async {
                              await c.flush();
                              await c.synchronize();
                            }),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            if (view != null && !view.rulesReady)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('此视图的部分规则暂不支持，保留原规则并按原始顺序只读显示'),
              ),
            if (view != null &&
                (view.filters.isNotEmpty || view.sorts.isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: Text(
                  '显示 ${view.matchedRows} / ${view.totalRows} 条记录${view.rows.any((r) => !r.loaded) ? ' · 部分记录待加载' : ''}',
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child:
                  !c.canRead ||
                      c.syncState == DatasetSyncState.forbidden ||
                      (widget.embedded &&
                          c.syncState == DatasetSyncState.removed)
                  ? const Center(child: Text('无法访问此数据集，请联系所有者'))
                  : view == null
                  ? const Center(child: Text('指定视图不可用，原引用保留'))
                  : !view.supportedLayout
                  ? const Center(child: Text('此视图的编辑能力尚未安装，原数据保留'))
                  : view.layout == 1
                  ? DatasetBoardSurface(
                      controller: c,
                      view: view,
                      editable: editable,
                      run: _run,
                      realtime: widget.realtime,
                    )
                  : _grid(view, editable),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _status(),
                      key: const ValueKey('dataset.status'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (c.syncState != DatasetSyncState.local)
                    IconButton(
                      tooltip: '立即同步',
                      onPressed: busy
                          ? null
                          : () => _run(() => c.synchronize()),
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
  Future<void> _editCell(
    String viewId,
    DatasetRow row,
    DatasetColumn column,
  ) async {
    final realtime = widget.realtime;
    realtime?.selectCell(
      viewId: viewId,
      rowId: row.id,
      fieldId: column.id,
      editing: true,
    );
    try {
      await showDatasetCellEditor(context, c, row, column);
    } finally {
      if (mounted) {
        try {
          realtime?.selectCell(
            viewId: viewId,
            rowId: row.id,
            fieldId: column.id,
            editing: false,
          );
        } on Object {
          realtime?.clearSelection();
        }
      }
    }
  }

  Widget _toolbar(bool board, Widget child) => board
      ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: child)
      : child;

  Widget _grid(DatasetViewProjection view, bool editable) => LayoutBuilder(
    builder: (context, box) {
      final width = math.max(
        180.0,
        (box.maxWidth - 44) / math.max(1, view.columns.length),
      );
      final border = Theme.of(context).colorScheme.outlineVariant;
      Widget cell(
        Widget child, {
        bool header = false,
        String? rowId,
        String? fieldId,
        String? semanticLabel,
      }) {
        final remote = rowId == null || fieldId == null
            ? null
            : datasetRemoteCellColor(widget.realtime, view.id, rowId, fieldId);
        return Semantics(
          label: remote == null ? semanticLabel : '$semanticLabel，协作者选中此单元格',
          child: Container(
            key: remote == null
                ? null
                : ValueKey('dataset.remote-cell.$rowId.$fieldId'),
            width: width,
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: header
                  ? Theme.of(context).colorScheme.surfaceContainerLow
                  : null,
              border: remote == null
                  ? Border(
                      right: BorderSide(color: border),
                      bottom: BorderSide(color: border),
                    )
                  : Border.all(color: remote, width: 2),
            ),
            child: child,
          ),
        );
      }

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width * view.columns.length + 44,
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 44,
                    height: 52,
                    child: Center(
                      child: Text(
                        '#',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                  for (final column in view.columns)
                    cell(
                      InkWell(
                        key: ValueKey('dataset.field.${column.id}'),
                        onTap: editable
                            ? () => showDatasetFieldEditor(
                                context,
                                c,
                                column.semanticType,
                                field: column,
                              )
                            : null,
                        child: SizedBox(
                          height: 52,
                          child: Row(
                            children: [
                              Icon(switch (column.semanticType) {
                                'checkbox' => Icons.check_box_outlined,
                                'number' => Icons.numbers,
                                'url' => Icons.link,
                                'singleSelect' => Icons.radio_button_checked,
                                'multiSelect' => Icons.checklist,
                                _ => Icons.text_fields,
                              }, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  column.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (editable)
                                const Icon(Icons.expand_more, size: 16),
                            ],
                          ),
                        ),
                      ),
                      header: true,
                    ),
                ],
              ),
              Expanded(
                child: view.rows.isEmpty
                    ? Center(
                        child: Text(
                          view.totalRows > 0 ? '没有符合筛选的记录' : '暂无记录，新增记录开始',
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: view.rows.length,
                        itemBuilder: (context, index) {
                          final row = view.rows[index];
                          return Row(
                            children: [
                              SizedBox(
                                width: 44,
                                height: 52,
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ),
                              ),
                              for (final column in view.columns)
                                cell(
                                  !row.loaded
                                      ? const Text('记录尚未加载')
                                      : column.semanticType == 'checkbox'
                                      ? Align(
                                          alignment: Alignment.centerLeft,
                                          child: Checkbox(
                                            key: ValueKey(
                                              'dataset.cell.${row.id}.${column.id}',
                                            ),
                                            value:
                                                row.cells[column.id]?.value ==
                                                true,
                                            onChanged:
                                                editable && column.editable
                                                ? (value) => _run(
                                                    () => c.setCell(
                                                      row,
                                                      column,
                                                      value,
                                                      expectedHash: row
                                                          .cells[column.id]!
                                                          .hash,
                                                    ),
                                                  )
                                                : null,
                                          ),
                                        )
                                      : InkWell(
                                          key: ValueKey(
                                            'dataset.cell.${row.id}.${column.id}',
                                          ),
                                          onTap:
                                              editable &&
                                                  column.editable &&
                                                  row
                                                          .cells[column.id]
                                                          ?.unresolvedDate !=
                                                      true &&
                                                  row
                                                          .cells[column.id]
                                                          ?.unresolvedNumber !=
                                                      true &&
                                                  (column.semanticType !=
                                                          'number' ||
                                                      row
                                                              .cells[column.id]
                                                              ?.numberInput !=
                                                          null)
                                              ? () => _editCell(
                                                  view.id,
                                                  row,
                                                  column,
                                                )
                                              : null,
                                          child: SizedBox.expand(
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child:
                                                  column.semanticType == 'date'
                                                  ? Text(
                                                      displayDateCell(
                                                        row.cells[column.id]!,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    )
                                                  : column.semanticType ==
                                                        'number'
                                                  ? Text(
                                                      displayNumberCell(
                                                        row.cells[column.id]!,
                                                      ),
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    )
                                                  : column.isChoice
                                                  ? DatasetChoiceCell(
                                                      column: column,
                                                      cell:
                                                          row.cells[column.id]!,
                                                    )
                                                  : Text(
                                                      column.editable
                                                          ? displayCell(
                                                              row
                                                                  .cells[column
                                                                      .id]
                                                                  ?.value,
                                                            )
                                                          : '此字段暂不可编辑',
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                            ),
                                          ),
                                        ),
                                  rowId: row.id,
                                  fieldId: column.id,
                                  semanticLabel:
                                      '第 ${index + 1} 行，${column.name}',
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
