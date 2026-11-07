import 'package:flutter/material.dart';
import 'controller.dart';
import 'projection.dart';
import 'dialogs.dart';
import 'date_ui.dart';
import 'record_ui.dart';
import 'realtime_session.dart';
import 'collaborators_view.dart';

final class _CardDrag {
  const _CardDrag(this.view, this.row);
  final DatasetViewProjection view;
  final DatasetRow row;
}

/// Board only renders derived original groups and row IDs. Commands, authority,
/// history, persistence and network remain with the shared domain session.
class DatasetBoardSurface extends StatelessWidget {
  const DatasetBoardSurface({
    super.key,
    required this.controller,
    required this.view,
    required this.editable,
    required this.run,
    this.realtime,
  });
  final DatasetController controller;
  final DatasetViewProjection view;
  final bool editable;
  final Future<void> Function(Future<void> Function()) run;
  final DatasetRealtimeSession? realtime;

  Future<void> _move(BuildContext context, DatasetRow row) async {
    final group = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: Text('移动到分组')),
              for (final group in view.board!.targets)
                ListTile(
                  key: ValueKey('dataset.move-group.${group.id}'),
                  minTileHeight: 48,
                  title: Text(group.name),
                  leading: const Icon(Icons.view_column_outlined),
                  onTap: () => Navigator.pop(context, group.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (group != null)
      await run(() => controller.moveBoardCard(view, row, group));
  }

  Widget _card(BuildContext context, DatasetRow row) {
    final titleField =
        view.columns.where((c) => c.id == 'title').firstOrNull ??
        view.columns.firstOrNull;
    final title = displayCell(row.cells[titleField?.id]?.value);
    final remote = datasetRemoteCellColor(
      realtime,
      view.id,
      row.id,
      view.board!.fieldId!,
    );
    final unresolved =
        row.cells[view.board!.fieldId]?.unresolvedOptions == true;
    final card = Card(
      key: ValueKey('dataset.card.${row.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: remote ?? Theme.of(context).colorScheme.outlineVariant,
          width: remote == null ? 1 : 2,
        ),
      ),
      child: InkWell(
        onTap: () => run(() async {
          realtime?.selectCell(
            viewId: view.id,
            rowId: row.id,
            fieldId: titleField?.id ?? view.board!.fieldId!,
          );
          await showDatasetRecordEditor(
            context,
            controller,
            view.id,
            row.id,
            allowEditing: editable && !unresolved,
          );
        }),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title.isEmpty ? '未命名记录' : title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  IconButton(
                    key: ValueKey('dataset.card-move.${row.id}'),
                    tooltip: '移动卡片',
                    onPressed: editable && !unresolved
                        ? () => _move(context, row)
                        : null,
                    icon: const Icon(Icons.drive_file_move_outline, size: 18),
                  ),
                ],
              ),
              for (final column in view.columns.where(
                (c) => c.id != titleField?.id && c.id != view.board!.fieldId,
              ))
                if (displayCell(row.cells[column.id]?.value).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      '${column.name}：${column.semanticType == 'date'
                          ? displayDateCell(row.cells[column.id]!)
                          : column.semanticType == 'number'
                          ? displayNumberCell(row.cells[column.id]!)
                          : displayCell(row.cells[column.id]?.value)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              if (unresolved) const Text('分组选项暂不支持，原值保留'),
            ],
          ),
        ),
      ),
    );
    if (!editable || unresolved) return card;
    return LongPressDraggable<_CardDrag>(
      data: _CardDrag(view, row),
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(width: 248, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final board = view.board!;
    final rows = {for (final row in view.rows) row.id: row};
    return Column(
      children: [
        if (board.unresolvedRowIds.isNotEmpty ||
            board.unloadedRowIds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${board.unresolvedRowIds.length} 条记录的分组暂不支持 · ${board.unloadedRowIds.length} 条待加载；原记录保留，可切换表格查看',
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - 24).clamp(244.0, 280.0);
              return ListView.separated(
                key: const ValueKey('dataset.board'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(12),
                itemCount: board.groups.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final group = board.groups[index];
                  return DragTarget<_CardDrag>(
                    onWillAcceptWithDetails: (d) =>
                        editable && d.data.view.id == view.id,
                    onAcceptWithDetails: (d) => run(
                      () => controller.moveBoardCard(
                        d.data.view,
                        d.data.row,
                        group.id,
                      ),
                    ),
                    builder: (context, candidates, rejected) => Container(
                      width: width,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: candidates.isEmpty
                            ? Theme.of(context).colorScheme.surfaceContainerLow
                            : Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: 44,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 8,
                                  color:
                                      Colors.primaries[group.color %
                                          Colors.primaries.length],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${group.name} · ${group.rowIds.length}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  key: ValueKey(
                                    'dataset.group-add.${group.id}',
                                  ),
                                  tooltip: '在${group.name}新增记录',
                                  onPressed: !editable
                                      ? null
                                      : () => run(() async {
                                          final id = await controller
                                              .addBoardCard(view, group.id);
                                          if (context.mounted)
                                            await showDatasetRecordEditor(
                                              context,
                                              controller,
                                              view.id,
                                              id,
                                            );
                                        }),
                                  icon: const Icon(Icons.add, size: 20),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView(
                              key: ValueKey('dataset.group.${group.id}'),
                              children: [
                                for (final id in group.rowIds)
                                  if (rows[id] case final row?)
                                    _card(context, row),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
