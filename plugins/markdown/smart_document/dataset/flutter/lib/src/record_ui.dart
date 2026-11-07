import 'package:flutter/material.dart';
import 'controller.dart';
import 'dialogs.dart';
import 'projection.dart';
import 'date_ui.dart';

/// An unfiltered record query, reusing all existing typed cell editors. A view
/// filters presentation; controller authority and original row references gate
/// access independently on every rebuild and every domain command.
Future<void> showDatasetRecordEditor(
  BuildContext context,
  DatasetController c,
  String viewId,
  String rowId, {
  bool allowEditing = true,
}) => showDialog<void>(
  context: context,
  builder: (_) => _RecordEditor(
    controller: c,
    viewId: viewId,
    rowId: rowId,
    allowEditing: allowEditing,
  ),
);

class _RecordEditor extends StatelessWidget {
  const _RecordEditor({
    required this.controller,
    required this.viewId,
    required this.rowId,
    required this.allowEditing,
  });
  final DatasetController controller;
  final String viewId, rowId;
  final bool allowEditing;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final view = controller.views.where((v) => v.id == viewId).firstOrNull;
      DatasetRow? row;
      try {
        if (view != null) row = controller.readRow(viewId, rowId);
      } on Object {
        /* Authority or dependency changed. */
      }
      final record = row;
      return AlertDialog(
        key: const ValueKey('dataset.record-dialog'),
        title: const Text('编辑新记录'),
        content: SizedBox(
          width: 480,
          child: record == null || view == null
              ? const Text('记录不可用，或访问权限已变更')
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!view.rows.any((r) => r.id == rowId))
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('该记录未匹配当前筛选，仍可在这里编辑。'),
                        ),
                      for (final column in view.columns)
                        ListTile(
                          key: ValueKey('dataset.record-field.${column.id}'),
                          minVerticalPadding: 12,
                          title: Text(column.name),
                          subtitle: Text(
                            column.semanticType == 'date'
                                ? displayDateCell(record.cells[column.id]!)
                                : column.semanticType == 'number'
                                ? displayNumberCell(record.cells[column.id]!)
                                : displayCell(record.cells[column.id]?.value),
                          ),
                          trailing: const Icon(Icons.edit_outlined, size: 18),
                          enabled:
                              allowEditing &&
                              controller.canWrite &&
                              column.editable &&
                              record.cells[column.id]?.unresolvedDate != true &&
                              record.cells[column.id]?.unresolvedNumber !=
                                  true &&
                              (column.semanticType != 'number' ||
                                  record.cells[column.id]?.numberInput !=
                                      null) &&
                              record.cells[column.id]?.unresolvedOptions !=
                                  true,
                          onTap: () async {
                            if (column.semanticType == 'checkbox') {
                              try {
                                await controller.setCell(
                                  record,
                                  column,
                                  record.cells[column.id]?.value != true,
                                  expectedHash: record.cells[column.id]!.hash,
                                );
                              } on Object {
                                if (context.mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('内容或权限已变化，请重新编辑'),
                                    ),
                                  );
                              }
                            } else {
                              await showDatasetCellEditor(
                                context,
                                controller,
                                record,
                                column,
                              );
                            }
                          },
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('完成'),
          ),
        ],
      );
    },
  );
}
