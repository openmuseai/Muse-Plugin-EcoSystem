import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:muse_resource_center_io/muse_resource_center_io.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';
import 'package:openmuse_dataset_plugin/openmuse_dataset_plugin.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final workbench = await DatasetWorkbench.open();
  runApp(DatasetApp(workbench: workbench));
}

/// A real public-SDK independent dataset fixture: resource creator -> private IO provider
/// -> ResourceCenterHub -> bounded ResourceEditorSession -> installed plugin.
/// No format-specific changes to the user's production Host are necessary.
final class DatasetWorkbench {
  DatasetWorkbench._(
    this.directory,
    this.hub,
    this.local,
    this.plugin,
    this.session,
  );
  final Directory directory;
  final ResourceCenterHub hub;
  final LocalResourceProvider local;
  final OpenMuseDatasetPlugin plugin;
  final ResourceEditorSession session;
  static const origin = String.fromEnvironment('SMARTDOC_ORIGIN');
  static const workspace = String.fromEnvironment('SMARTDOC_WORKSPACE');
  static const aliceToken = String.fromEnvironment('SMARTDOC_ALICE_TOKEN');
  static const bobToken = String.fromEnvironment('SMARTDOC_BOB_TOKEN');
  static const run = String.fromEnvironment(
    'SMARTDOC_RUN',
    defaultValue: 'local',
  );
  static bool get cloudEnabled =>
      origin.isNotEmpty && workspace.isNotEmpty && aliceToken.isNotEmpty;

  static Future<DatasetWorkbench> open({
    bool realtime = false,
    http.Client Function(int)? transportClientFactory,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/DatasetStage1/$run');
    await directory.create(recursive: true);
    final hub = ResourceCenterHub(scope: 'dataset-$run');
    final local = await LocalResourceProvider.open(
      Directory('${directory.path}/resources'),
      scope: hub.scope,
      label: '阶段一验证资源',
      deviceLabel: '当前设备',
      generation: () => hub.generation,
    );
    hub.register(local);
    final access = ResourceAccess(
      scope: hub.scope,
      audience: 'dataset-stage1',
      generation: hub.generation,
      expiresAtMs:
          DateTime.now().millisecondsSinceEpoch +
          const Duration(days: 1).inMilliseconds,
      operations: ResourceOperation.values.toSet(),
    );
    final plugin = OpenMuseDatasetPlugin(
      core: NativeDatasetCore(),
      storeFactory: (session) async => FileSnapshotStore(
        File(
          '${directory.path}/cache/${session.record.identity.resource}.json',
        ),
      ),
      collaborationFactory: cloudEnabled
          ? (_) => providerFor('alice', clientFactory: transportClientFactory)
          : null,
      realtimeFactory: cloudEnabled && realtime
          ? (session, controller) async {
              final wire = await loadRealtimeWireCore();
              return DatasetRealtimeSession(
                controller: controller,
                presenceCore: wire,
                connection: AppFlowyRealtimeConnection(
                  origin: Uri.parse(origin),
                  workspaceId: workspace,
                  deviceId: 'dataset-realtime-$run',
                  clientId: DateTime.now().microsecondsSinceEpoch.toString(),
                  accessToken: () async => aliceToken,
                  codec: AppFlowyRealtimeCodec(wire),
                ),
              );
            }
          : null,
    );
    await plugin.activate(
      OpenMusePluginContext(executeHostCommand: (_, _) async => null),
    );
    final entries = await local.list('root', access);
    ResourceRecord? record;
    for (final e in entries.entries) {
      if (e.resource?.mediaType == datasetMediaType) {
        record = e.resource;
        break;
      }
    }
    if (record == null) {
      final seed = await plugin.createResource('dataset.database', {});
      record = await local.create(
        parentRef: 'root',
        name: '数据库 · 协作验证.musedataset',
        mediaType: seed.mediaType,
        bytes: seed.bytes,
        idempotencyKey: 'dataset-initial-resource',
        access: access,
      );
    }
    final opened = await hub.resolve(record.reference(), access);
    final session = ResourceEditorSession(
      opened: opened,
      allowEditing: true,
      commitContent: (base, bytes, key) =>
          local.commit(record!.identity.resource, base, bytes, key, access),
      onOpened: (r) {
        hub.recordOpened(r, 'dataset.database');
      },
      onChanged: (r) {
        hub.refreshRecord(r);
      },
    );
    return DatasetWorkbench._(directory, hub, local, plugin, session);
  }

  static DatasetProviderFactory providerFor(
    String user, {
    http.Client Function(int)? clientFactory,
  }) =>
      (type) => AppFlowyObjectTransport(
        origin: Uri.parse(origin),
        workspaceId: workspace,
        deviceId: 'dataset-native-$run-$user-$type',
        accessToken: () async => user == 'alice' ? aliceToken : bobToken,
        binding: datasetBinding(type),
        collabType: type,
        client: clientFactory?.call(type),
      );

  DatasetController? get controller =>
      plugin.activeController(session.record.identity);
  Future<void> close() async {
    if (!await session.prepareToClose()) {
      throw const ResourceFailure('UNSAVED_CHANGES');
    }
    await plugin.deactivate();
    session.dispose();
    await local.close();
    await hub.dispose();
  }
}

final class DatasetApp extends StatelessWidget {
  const DatasetApp({super.key, required this.workbench});
  final DatasetWorkbench workbench;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4c63d9)),
    ),
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    locale: const Locale('zh', 'CN'),
    home: Scaffold(
      body: SafeArea(
        child: RepaintBoundary(
          key: const ValueKey('dataset.surface'),
          child: workbench.plugin.buildResourceEditor(
            context,
            'dataset.database',
            workbench.session,
          ),
        ),
      ),
    ),
  );
}
