/// Read projection only; opaque original CRDT state remains authoritative.
final class DatasetColumn {
  DatasetColumn.fromJson(Map value)
    : id = value['id'] as String,
      name = value['name'] as String,
      semanticType = value['semanticType'] as String,
      storageType = value['storageType'] as int,
      editable = value['editable'] == true,
      fieldHash = value['fieldHash'] as String?,
      options = List.unmodifiable(
        (value['options'] as List? ?? const []).map(
          (v) => DatasetChoice.fromJson(v as Map),
        ),
      );
  final String id, name, semanticType;
  final int storageType;
  final bool editable;
  final String? fieldHash;
  final List<DatasetChoice> options;
  bool get isChoice =>
      semanticType == 'singleSelect' || semanticType == 'multiSelect';
}

final class DatasetChoice {
  DatasetChoice.fromJson(Map value)
    : id = value['id'] as String,
      name = value['name'] as String,
      color = value['color'] as int;
  final String id, name;
  final int color;
}

final class DatasetOptionDraft {
  const DatasetOptionDraft({required this.name, this.color = 0});
  final String name;
  final int color;
}

final class DatasetCell {
  DatasetCell.fromJson(Map value)
    : value = value['value'],
      hash = value['hash'] as String,
      selectedOptionIds = List.unmodifiable(
        (value['selectedOptionIds'] as List? ?? const []).cast<String>(),
      ),
      unresolvedOptions = value['unresolvedOptions'] == true;
  final Object? value;
  final String hash;
  final List<String> selectedOptionIds;
  final bool unresolvedOptions;
}

final class DatasetRow {
  DatasetRow.fromJson(Map value)
    : id = value['id'] as String,
      loaded = value['loaded'] == true,
      cells = Map.unmodifiable({
        for (final entry in (value['cells'] as Map? ?? {}).entries)
          entry.key as String: DatasetCell.fromJson(entry.value as Map),
      });
  final String id;
  final bool loaded;
  final Map<String, DatasetCell> cells;
}

final class DatasetViewProjection {
  DatasetViewProjection.fromJson(Map value)
    : id = value['id'] as String,
      name = value['name'] as String,
      layout = value['layout'] as int,
      columns = List.unmodifiable(
        (value['columns'] as List).map((v) => DatasetColumn.fromJson(v as Map)),
      ),
      rows = List.unmodifiable(
        (value['rows'] as List).map((v) => DatasetRow.fromJson(v as Map)),
      );
  final String id, name;
  final int layout;
  final List<DatasetColumn> columns;
  final List<DatasetRow> rows;
}
