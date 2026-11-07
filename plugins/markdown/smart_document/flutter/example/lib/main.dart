import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:muse_resource_center_io/muse_resource_center_io.dart';
import 'package:openmuse_plugin_sdk/openmuse_plugin_sdk.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';
import 'package:openmuse_smart_document_plugin/openmuse_smart_document_plugin.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final workbench = await StageOneWorkbench.open();
  runApp(StageOneApp(workbench: workbench));
}

/// A real public-SDK workbench fixture: resource creator -> private IO provider
/// -> ResourceCenterHub -> bounded ResourceEditorSession -> installed plugin.
/// No format-specific changes to the user's production Host are necessary.
final class StageOneWorkbench {
  StageOneWorkbench._(
    this.directory,
    this.hub,
    this.local,
    this.plugin,
    this.session,
  );
  final Directory directory;
  final ResourceCenterHub hub;
  final LocalResourceProvider local;
  final OpenMuseSmartDocumentPlugin plugin;
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

  static Future<StageOneWorkbench> open({
    DocumentImagePicker? imagePicker,
    bool realtime = false,
    AppFlowySocketFactory? realtimeSocketFactory,
    ResourceEmbedHost? Function(ResourceEditorSession)? embedHostFactory,
    http.Client Function()? transportClientFactory,
  }) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/SmartDocumentStage1/$run');
    await directory.create(recursive: true);
    final hub = ResourceCenterHub(scope: 'stage1-$run');
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
      audience: 'smart-document-stage1',
      generation: hub.generation,
      expiresAtMs:
          DateTime.now().millisecondsSinceEpoch +
          const Duration(days: 1).inMilliseconds,
      operations: ResourceOperation.values.toSet(),
    );
    final plugin = OpenMuseSmartDocumentPlugin(
      imagePicker: imagePicker,
      embedHostFactory: embedHostFactory,
      realtimeFactory: cloudEnabled && realtime
          ? (session, controller) async {
              final wire = await loadRealtimeWireCore();
              final clientId = DateTime.now().microsecondsSinceEpoch.toString();
              return DocumentRealtimeSession(
                controller: controller,
                presenceCore: wire,
                connection: AppFlowyRealtimeConnection(
                  origin: Uri.parse(origin),
                  workspaceId: workspace,
                  deviceId: 'stage1-realtime-$run',
                  clientId: clientId,
                  accessToken: () async => aliceToken,
                  codec: AppFlowyRealtimeCodec(wire),
                  socketFactory: realtimeSocketFactory,
                ),
              );
            }
          : null,
      storeFactory: (session) async => FileDocumentStore(
        File(
          '${directory.path}/cache/${session.record.identity.resource}.json',
        ),
      ),
      assetFactory: (session) async {
        final resource = session.record.identity.resource;
        final cache = DocumentStoreAssetCache(
          (key) => FileDocumentStore(
            File('${directory.path}/assets/$resource/$key.json'),
          ),
        );
        return cloudEnabled
            ? CachedAssetRepository(
                source: CloudAssetRepository(
                  origin: Uri.parse(origin),
                  workspaceId: workspace,
                  accessToken: () async => aliceToken,
                ),
                cache: cache,
                allowOffline: () => true,
              )
            : LocalAssetRepository(scope: resource, cache: cache);
      },
      draftStoreFactory: (session) async => FileDocumentStore(
        File(
          '${directory.path}/assets/${session.record.identity.resource}/draft.json',
        ),
      ),
      providerFactory: cloudEnabled
          ? (_) => AppFlowyCollaborationProvider(
              origin: Uri.parse(origin),
              workspaceId: workspace,
              deviceId: 'stage1-native-alice',
              accessToken: () async => aliceToken,
              client: transportClientFactory?.call(),
            )
          : null,
    );
    await plugin.activate(
      OpenMusePluginContext(executeHostCommand: (_, _) async => null),
    );
    final entries = await local.list('root', access);
    ResourceRecord? record;
    for (final e in entries.entries) {
      if (e.resource?.mediaType == smartDocumentMediaType) {
        record = e.resource;
        break;
      }
    }
    if (record == null) {
      final seed = await plugin.createResource('smart-document.document', {});
      record = await local.create(
        parentRef: 'root',
        name: '智能文档 · 协作验证.musedoc',
        mediaType: seed.mediaType,
        bytes: seed.bytes,
        idempotencyKey: 'stage1-initial-document',
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
        hub.recordOpened(r, 'smart-document.document');
      },
      onChanged: (r) {
        hub.refreshRecord(r);
      },
    );
    return StageOneWorkbench._(directory, hub, local, plugin, session);
  }

  SmartDocumentController? get controller =>
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

final class StageOneApp extends StatelessWidget {
  const StageOneApp({super.key, required this.workbench});
  final StageOneWorkbench workbench;
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
      AppFlowyEditorLocalizations.delegate,
    ],
    supportedLocales: AppFlowyEditorLocalizations.delegate.supportedLocales,
    home: Scaffold(
      body: RepaintBoundary(
        key: const ValueKey('stage1.surface'),
        child: workbench.plugin.buildResourceEditor(
          context,
          'smart-document.document',
          workbench.session,
        ),
      ),
    ),
  );
}
