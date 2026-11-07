import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openmuse_smart_document/openmuse_smart_document.dart';

const workspace = '041c01d0-831a-408a-b8fa-190d40dd9e93';
const owner = '041c01d0-831a-408a-b8fa-190d40dd9e94';
final bytes = Uint8List.fromList([1, 2, 3, 4]);
AssetReference reference() => AssetReference(
  provider: 'appflowy.private-assets/1',
  scope: workspace,
  owner: owner,
  key: sha256.convert(bytes).toString(),
  mediaType: 'image/png',
  byteLength: 4,
  sha256: sha256.convert(bytes).toString(),
);

class Cache implements AssetCache {
  Uint8List? value;
  @override
  Future<Uint8List?> read(AssetReference ref) async => value;
  @override
  Future<void> write(AssetReference ref, Uint8List bytes) async {
    value = bytes;
  }
}

void main() {
  test(
    'neutral references reject credentials fields and malformed integrity metadata',
    () {
      final ref = reference();
      expect(AssetReference.fromJson(ref.toJson()).toJson(), ref.toJson());
      expect(
        () => AssetReference.fromJson({...ref.toJson(), 'token': 'secret'}),
        throwsFormatException,
      );
      expect(
        () => AssetReference.fromJson({...ref.toJson(), 'sha256': 'BAD'}),
        throwsFormatException,
      );
      expect(
        () => AssetReference.fromJson({...ref.toJson(), 'byteLength': 0}),
        throwsFormatException,
      );
    },
  );
  test(
    'cloud repository uses scoped authenticated routes, validates receipt and bytes',
    () async {
      final ref = reference();
      var calls = 0;
      final repository = CloudAssetRepository(
        origin: Uri.parse('http://127.0.0.1:18000'),
        workspaceId: workspace,
        accessToken: () async => 'synthetic-token',
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          expect(request.headers['Authorization'], 'Bearer synthetic-token');
          expect(
            request.url.path,
            '/api/file_storage/$workspace/private/$owner/blob/${ref.key}',
          );
          calls++;
          if (request.method == 'GET') return http.Response.bytes(bytes, 200);
          expect(request.bodyBytes, bytes);
          return http.Response(
            jsonEncode({
              'provider': ref.provider,
              'scope': ref.scope,
              'owner': ref.owner,
              'key': ref.key,
              'media_type': ref.mediaType,
              'byte_length': ref.byteLength,
              'sha256': ref.sha256,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(
        (await repository.put(
          owner: owner,
          bytes: bytes,
          mediaType: 'image/png',
        )).toJson(),
        ref.toJson(),
      );
      expect(await repository.read(ref), bytes);
      expect(calls, 2);
      repository.close();
      await expectLater(repository.read(ref), throwsA(isA<AssetFailure>()));
    },
  );
  test(
    'redirect, foreign scope and corrupted blob are rejected before cache writes',
    () async {
      for (final status in [302, 200]) {
        final r = CloudAssetRepository(
          origin: Uri.parse('https://example.test'),
          workspaceId: workspace,
          accessToken: () async => 't',
          client: MockClient(
            (_) async => http.Response.bytes(
              [9],
              status,
              headers: {'location': 'https://elsewhere.test'},
            ),
          ),
        );
        await expectLater(r.read(reference()), throwsA(isA<AssetFailure>()));
        r.close();
      }
      final r = CloudAssetRepository(
        origin: Uri.parse('https://example.test'),
        workspaceId: workspace,
        accessToken: () async => throw StateError('must not request'),
      );
      await expectLater(
        r.read(
          AssetReference.fromJson({...reference().toJson(), 'scope': owner}),
        ),
        throwsA(isA<AssetFailure>()),
      );
      r.close();
    },
  );
  test(
    'cached authorized bytes cannot bypass denial/not-found; only explicit offline fallback',
    () async {
      final cache = Cache()..value = bytes;
      for (final status in [401, 403, 404]) {
        final source = CloudAssetRepository(
          origin: Uri.parse('https://example.test'),
          workspaceId: workspace,
          accessToken: () async => 't',
          client: MockClient((_) async => http.Response('', status)),
        );
        final r = CachedAssetRepository(
          source: source,
          cache: cache,
          allowOffline: () => true,
        );
        await expectLater(r.read(reference()), throwsA(isA<AssetFailure>()));
        r.close();
      }
      for (final allow in [false, true]) {
        final source = CloudAssetRepository(
          origin: Uri.parse('https://example.test'),
          workspaceId: workspace,
          accessToken: () async => 't',
          client: MockClient(
            (_) async => throw http.ClientException('offline'),
          ),
        );
        final r = CachedAssetRepository(
          source: source,
          cache: cache,
          allowOffline: () => allow,
        );
        if (allow) {
          expect(await r.read(reference()), bytes);
        } else {
          await expectLater(r.read(reference()), throwsA(isA<AssetFailure>()));
        }
        r.close();
      }
    },
  );
}
