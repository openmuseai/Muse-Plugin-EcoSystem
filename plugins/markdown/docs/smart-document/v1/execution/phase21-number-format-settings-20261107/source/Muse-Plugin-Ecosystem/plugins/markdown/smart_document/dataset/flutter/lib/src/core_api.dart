import 'package:muse_collab_contract/muse_collab_contract.dart';
export 'package:muse_collab_contract/muse_collab_contract.dart';

CollaborationBinding datasetBinding(int collabType) {
  if (!{1, 4}.contains(collabType))
    throw const DatasetFailure('INVALID_COLLAB_TYPE');
  return CollaborationBinding(
    protocol: 'appflowy.full-sync/1',
    engine: 'appflowy-collab/e59260e524f33104b0ddcd6bb8f6218cad0f7e18',
    encoding: 'yrs.update-v1',
    schema: collabType == 1
        ? 'appflowy.database/0.2'
        : 'appflowy.database-row/0.2',
    epoch: 0,
  );
}

abstract interface class DatasetCore {
  Map<String, dynamic> call(Map<String, dynamic> request);
}

final class DatasetFailure implements Exception {
  const DatasetFailure(this.code);
  final String code;
  @override
  String toString() => 'DatasetFailure($code)';
}
