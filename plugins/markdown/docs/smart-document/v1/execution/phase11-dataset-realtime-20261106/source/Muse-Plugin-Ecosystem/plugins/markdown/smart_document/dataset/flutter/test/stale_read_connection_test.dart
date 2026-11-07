import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:openmuse_dataset/openmuse_dataset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
    'idempotent read recovers when a paused client missed the server keep-alive close',
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
      final p = AppFlowyObjectTransport(
        origin: Uri.parse(f['origin'] as String),
        workspaceId: config['SMARTDOC_WORKSPACE'] as String,
        accessToken: () async => f['users']['alice']['accessToken'] as String,
        deviceId: 'native-stale-read-qualification',
        collabType: 1,
        binding: datasetBinding(1),
      );
      try {
        expect(
          await p.readState(config['CHOICES_OBJECT'] as String),
          isNotEmpty,
        );
        // Deliberately block this test isolate across the server's idle timeout.
        // A frozen/native-busy client cannot process the remote socket FIN in time.
        sleep(const Duration(seconds: 8));
        expect(
          await p.readState(config['CHOICES_OBJECT'] as String),
          isNotEmpty,
        );
      } finally {
        p.close();
      }
    },
  );
}
