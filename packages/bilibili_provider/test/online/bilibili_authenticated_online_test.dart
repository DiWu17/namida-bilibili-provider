@Tags(<String>['online', 'authenticated'])
library;

import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:online_media_provider/online_media_provider.dart';
import 'package:test/test.dart';

/// Authenticated online checks for the Bilibili account layer.
///
/// Nothing here runs without credentials:
///
/// - the file is tagged `online` + `authenticated` and `dart_test.yaml` skips both
///   tags, so a plain `dart test` never touches them;
/// - the groups also declare `skip:`, and every test self-skips at runtime,
///   because `--run-skipped` overrides a declared skip. Without that runtime
///   guard, `dart test --tags authenticated --run-skipped` would throw a
///   null-check error instead of reporting a skip.
///
/// Environment variables:
///
/// | name | needed for |
/// |---|---|
/// | `BILIBILI_TEST_COOKIES` | every group; the user's own `Cookie` header |
/// | `BILIBILI_TEST_FOLDER_ID` | optional; folder to browse (default: first created folder) |
/// | `BILIBILI_TEST_BVID` | optional; video used for the favorites -> playback bridge |
/// | `BILIBILI_TEST_WRITE_FOLDER_ID` | opt-in; folder used by the mutating round trip |
/// | `BILIBILI_TEST_WRITE_BVID` | opt-in; video used by the mutating round trip |
///
/// The cookie value is only read from the environment, is never printed, and never
/// appears in an assertion message.
///
/// Signals that a cookie is missing on purpose:
///
/// - [BilibiliAuthenticationException] with platform code `-101` means the session
///   expired;
/// - the write round trip additionally requires the `bili_jct` csrf token and fails
///   fast without sending a request when it is absent.
const String cookiesEnvVar = 'BILIBILI_TEST_COOKIES';
const String folderEnvVar = 'BILIBILI_TEST_FOLDER_ID';
const String bvidEnvVar = 'BILIBILI_TEST_BVID';
const String writeFolderEnvVar = 'BILIBILI_TEST_WRITE_FOLDER_ID';
const String writeBvidEnvVar = 'BILIBILI_TEST_WRITE_BVID';

const String _needsCookies =
    'Set $cookiesEnvVar to run authenticated online checks.';
const String _needsWriteConfiguration =
    'Set $writeFolderEnvVar and $writeBvidEnvVar to run the mutating '
    'favorite round trip.';

String? _envValue(String name) {
  final raw = Platform.environment[name];
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  return raw.trim();
}

int? _envInt(String name) {
  final raw = _envValue(name);
  if (raw == null) {
    return null;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed <= 0) {
    fail('$name must be a positive integer.');
  }
  return parsed;
}

/// Folder to exercise: the explicit override, else the first created one.
Future<int?> _resolveFolderId(BilibiliAccountManager manager, int mid) async {
  final explicit = _envInt(folderEnvVar);
  if (explicit != null) {
    return explicit;
  }
  final folders = await manager.client.getCreatedFavoriteFolders(mid: mid);
  return folders.isEmpty ? null : folders.first.mediaId;
}

/// Video to resolve: the explicit override, else the first favorite.
Future<String?> _pickBvid(BilibiliAccountManager manager, int mid) async {
  final explicit = _envValue(bvidEnvVar);
  if (explicit != null) {
    return explicit;
  }

  final folderId = await _resolveFolderId(manager, mid);
  if (folderId == null) {
    return null;
  }
  final media = await manager.client.getAllFavoriteMedia(
    mediaId: folderId,
    maxPages: 3,
  );
  return media.isEmpty ? null : media.first.id.id;
}

void main() {
  final cookieHeader = _envValue(cookiesEnvVar);
  final hasCredentials = cookieHeader != null;

  group(
    'authenticated account (read-only)',
    skip: hasCredentials ? null : _needsCookies,
    () {
      BilibiliAccountManager? activeManager;
      BilibiliAccountInfo? activeAccount;

      setUpAll(() async {
        final cookies = cookieHeader;
        if (cookies == null) {
          return;
        }

        final manager = BilibiliAccountManager();
        await manager.signIn(cookies);
        final info = await manager.getCurrentAccount(forceRefresh: true);
        if (info == null) {
          fail(
            'nav accepted the cookie but reported no account; '
            'the session may have just expired.',
          );
        }

        activeManager = manager;
        activeAccount = info;
        printOnFailure('account mid: ${info.mid}');
      });

      tearDownAll(() async {
        await activeManager?.dispose();
      });

      test('signIn yields an authenticated session', () {
        final manager = activeManager;
        final account = activeAccount;
        if (manager == null || account == null) {
          markTestSkipped(_needsCookies);
          return;
        }

        expect(manager.isAnonymous, isFalse);
        expect(manager.cookieValidity.isAuthenticated, isTrue);
        expect(manager.signedInAccounts, hasLength(1));

        expect(account.mid, greaterThan(0));
        expect(account.name, isNotEmpty);
        expect(manager.authProvider.cookieHeader, isNotNull);

        // The session must never expose the raw cookie through toString().
        expect(manager.activeSession.toString(), isNot(contains('SESSDATA=')));
        expect(manager.toString(), isNot(contains('SESSDATA=')));
      });

      test('myinfo agrees with nav', () async {
        final manager = activeManager;
        final account = activeAccount;
        if (manager == null || account == null) {
          markTestSkipped(_needsCookies);
          return;
        }

        final info = await manager.client.getMyInfo();

        expect(info.mid, account.mid);
        expect(info.name, isNotEmpty);
      });

      test(
        'favorite folders load and the first page maps to OnlineMedia',
        () async {
          final manager = activeManager;
          final account = activeAccount;
          if (manager == null || account == null) {
            markTestSkipped(_needsCookies);
            return;
          }

          final folders = await manager.client.getCreatedFavoriteFolders(
            mid: account.mid,
          );
          for (final folder in folders) {
            expect(folder.mediaId, greaterThan(0));
            expect(folder.ownerMid, anyOf(isNull, account.mid));
          }

          final folderId = await _resolveFolderId(manager, account.mid);
          if (folderId == null) {
            markTestSkipped(
              'account has no favorite folders and $folderEnvVar is not set',
            );
            return;
          }

          final page = await manager.client.getFavoriteResources(
            mediaId: folderId,
            pageSize: BilibiliAccountClient.maxFavoritePageSize,
          );

          expect(page.entries.length, lessThanOrEqualTo(page.pageSize));
          expect(page.page, 1);

          for (final media in page.media) {
            expect(media.id.provider, 'bilibili');
            expect(media.id.id, isNotEmpty);
            expect(
              media.id.subId,
              isNull,
              reason: 'favorite entries never carry a CID',
            );
          }
        },
      );

      test('favorites bridge resolves a playable part', () async {
        final manager = activeManager;
        final account = activeAccount;
        if (manager == null || account == null) {
          markTestSkipped(_needsCookies);
          return;
        }

        final bvid = await _pickBvid(manager, account.mid);
        if (bvid == null) {
          markTestSkipped('no playable favorite and $bvidEnvVar is not set');
          return;
        }

        final provider = manager.createMediaProvider();
        final resolved = await provider.resolveById(
          OnlineMediaId(provider: 'bilibili', id: bvid),
        );

        expect(resolved.id.id, bvid);
        expect(resolved.id.subId, isNotNull);
        expect(resolved.id.subId, isNotEmpty);
        expect(resolved.parts, isNotEmpty);

        final playback = await provider.getPlayback(resolved.id);

        expect(
          playback.audioStreams.isNotEmpty || playback.muxedStreams.isNotEmpty,
          isTrue,
          reason:
              'an authenticated session must yield at least one audio source',
        );
        // Stream URLs are credentials in URL form; never assert on them.
        expect(playback.media.id.id, bvid);
      });
    },
  );

  final writeFolderId = _envInt(writeFolderEnvVar);
  final writeBvid = _envValue(writeBvidEnvVar);
  final hasWriteConfiguration = writeFolderId != null && writeBvid != null;
  final writeSkipReason = !hasCredentials
      ? _needsCookies
      : (hasWriteConfiguration ? null : _needsWriteConfiguration);

  group(
    'authenticated favorite write round trip (opt-in)',
    skip: writeSkipReason,
    () {
      BilibiliAccountManager? writeManager;
      int? writeAid;

      setUpAll(() async {
        // Read from the environment here rather than in the group body, because
        // `--run-skipped` executes the body even when the declared skip applies.
        final cookies = cookieHeader;
        final folder = writeFolderId;
        final bvid = writeBvid;
        if (cookies == null || folder == null || bvid == null) {
          return;
        }

        final manager = BilibiliAccountManager();
        await manager.signIn(cookies);

        // The write API takes a numeric aid, so read it from public metadata.
        final media = await manager.createMediaProvider().resolve(
          Uri.parse('https://www.bilibili.com/video/$bvid'),
        );
        final rawAid = media.extra['aid'];
        if (rawAid is! int || rawAid <= 0) {
          fail('could not read the numeric aid for $bvid');
        }

        writeManager = manager;
        writeAid = rawAid;
      });

      tearDownAll(() async {
        await writeManager?.dispose();
      });

      test(
        'adding a favorite is visible and the original state is restored',
        () async {
          final manager = writeManager;
          final aid = writeAid;
          final folderId = writeFolderId;
          if (manager == null || aid == null || folderId == null) {
            markTestSkipped(writeSkipReason ?? _needsWriteConfiguration);
            return;
          }

          Future<bool> present() async {
            final items = await manager.client.getAllFavoriteMedia(
              mediaId: folderId,
              maxPages: 5,
            );
            return items.any((item) => item.extra['aid'] == aid);
          }

          final initiallyPresent = await present();

          if (initiallyPresent) {
            // Already favorited: prove the write path is authorized and leave the
            // account exactly as it was found.
            await manager.client.addFavorite(
              aid: aid,
              folderIds: <int>[folderId],
            );
            expect(await present(), isTrue);
            return;
          }

          await manager.client.addFavorite(
            aid: aid,
            folderIds: <int>[folderId],
          );
          expect(
            await present(),
            isTrue,
            reason: 'the added favorite was not listed',
          );

          await manager.client.removeFavorite(
            aid: aid,
            folderIds: <int>[folderId],
          );
          expect(
            await present(),
            isFalse,
            reason: 'the removed favorite is still listed',
          );
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    },
  );
}
