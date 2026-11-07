import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'diagnose native read and projection timing for same browser source',
    () async {
      final f =
          jsonDecode(await File('../../.build/e2e-fixture.json').readAsString())
              as Map;
      final config =
          jsonDecode(
                await File(
                  '../../.build/choices-web-public.json',
                ).readAsString(),
              )
              as Map;
      final clock = Stopwatch()..start();
      void stamp(String step, [int? bytes]) => print(
        jsonEncode({
          'step': step,
          'milliseconds': clock.elapsedMilliseconds,
          if (bytes != null) 'bytes': bytes,
        }),
      );
      AppFlowyObjectTransport provider(int type) => AppFlowyObjectTransport(
        origin: Uri.parse(f['origin'] as String),
        workspaceId: config['SMARTDOC_WORKSPACE'] as String,
        accessToken: () async => f['users']['alice']['accessToken'] as String,
        deviceId: 'native-choice-diagnostic',
        collabType: type,
        binding: datasetBinding(type),
      );
      final root = provider(1), row = provider(4);
      String? handle;
      final core = NativeDatasetCore();
      try {
        stamp('start');
        final state = await root.readState(config['CHOICES_OBJECT'] as String);
        stamp('first-root-read', state!.length);
        final opened = core.call({
          'action': 'open',
          'objectId': config['CHOICES_OBJECT'],
          'bundle': {
            'profile': 'muse.dataset.bundle/0.1',
            'objectId': config['CHOICES_OBJECT'],
            'objects': [
              {
                'objectId': config['CHOICES_OBJECT'],
                'collabType': 1,
                'docState': base64Encode(state),
              },
            ],
          },
        });
        handle = opened['handle'] as String;
        stamp('native-root-open');
        final second = await root.readState(config['CHOICES_OBJECT'] as String);
        stamp('second-root-read', second!.length);
        final child = await row.readState(config['CHOICES_ROW'] as String);
        stamp('row-read', child!.length);
        final merged = core.call({
          'action': 'applyUpdate',
          'handle': handle,
          'objectId': config['CHOICES_ROW'],
          'update': base64Encode(child),
        });
        stamp('native-row-merge');
        expect((merged['views'] as List).first['rows'][0]['loaded'], true);
      } finally {
        root.close();
        row.close();
        if (handle != null) core.call({'action': 'close', 'handle': handle});
      }
    },
  );
}
