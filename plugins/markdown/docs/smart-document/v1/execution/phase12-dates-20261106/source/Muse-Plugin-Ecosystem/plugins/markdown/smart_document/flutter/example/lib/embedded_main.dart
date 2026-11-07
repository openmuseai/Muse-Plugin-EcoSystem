import 'package:flutter/material.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_dataset_plugin/openmuse_dataset_plugin.dart';
import 'dataset_main.dart';
import 'main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final w = await EmbeddedWorkbench.open();
  runApp(StageOneApp(workbench: w.document));
}

/// Host composition through two separately authorized public resource sessions.
/// The fixture's catalog is deliberately a single, explicit synthetic resource;
/// the document cannot resolve arbitrary IDs, paths, origins or resource bytes.
final class EmbeddedWorkbench {
  EmbeddedWorkbench._(this.document, this.dataset, this.registry, this.target);
  final StageOneWorkbench document;
  final DatasetWorkbench dataset;
  final DatasetEmbedRegistry registry;
  final ResourceEmbedTarget target;
  static Future<EmbeddedWorkbench> open({bool realtime = false}) async {
    final dataset = await DatasetWorkbench.open(realtime: realtime);
    final bundle = OpenMuseDatasetPlugin.decode(dataset.session.bytes);
    final state = dataset.plugin.core.call({
      'action': 'open',
      'objectId': bundle['objectId'],
      'bundle': bundle,
    });
    late String viewId;
    try {
      viewId = (state['views'] as List).first['id'] as String;
    } finally {
      dataset.plugin.core.call({'action': 'close', 'handle': state['handle']});
    }
    final target = ResourceEmbedTarget(
      reference: ResourceReference(identity: dataset.session.record.identity),
      surface: 'dataset.grid',
      selector: {'objectId': bundle['objectId'] as String, 'viewId': viewId},
    );
    final registry = DatasetEmbedRegistry(
      open: (request) async {
        if (request.reference.identity != target.reference.identity ||
            request.reference.pinned ||
            request.selector['objectId'] != target.selector['objectId']) {
          throw const ResourceFailure('RESOURCE_NOT_AUTHORIZED');
        }
        return dataset.plugin.openEmbeddedSession(dataset.session);
      },
    );
    final host = ResourceEmbedHost(
      build: registry.build,
      pick: (context, surface) async {
        if (surface != 'dataset.grid') {
          throw const ResourceFailure('HANDLER_UNAVAILABLE');
        }
        return showModalBottomSheet<ResourceEmbedTarget>(
          context: context,
          builder: (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('选择数据库'),
                ),
                ListTile(
                  key: const ValueKey('embed.pick-dataset'),
                  leading: const Icon(Icons.table_chart_outlined),
                  title: const Text('项目数据库'),
                  subtitle: const Text('引用现有数据库，与原资源共享修改'),
                  onTap: () => Navigator.of(ctx).pop(target),
                ),
              ],
            ),
          ),
        );
      },
    );
    final document = await StageOneWorkbench.open(
      embedHostFactory: (_) => host,
    );
    return EmbeddedWorkbench._(document, dataset, registry, target);
  }

  Future<void> close() async {
    await registry.close();
    await document.close();
    await dataset.close();
  }
}
