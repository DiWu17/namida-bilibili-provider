@Tags(<String>['online', 'authenticated'])
library;

import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:online_media_provider/online_media_provider.dart';
import 'package:test/test.dart';

/// Authenticated online checks for the Bilibili account layer.
///
/// Nothing here runs by default:
///
/// - the file is tagged `online` + `authenticated`, and `dart_test.yaml` skips
///   both tags;
/// - every group self-skips when its environment variables are missing, so
///   `--run-skipped` cannot accidentally hit the network without credentials.
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
/// The cookie value is only read from the environment, is never printed, and
/// never appears in an assertion message. `--reporter expanded` does not change
/// that.
///
/// Signals that a cookie is missing on purpose:
///
/// - [BilibiliAuthenticationException] with platform code `-101` means the
///   session expired;
/// - the write round trip additionally requires the `bili_jct` csrf token, and
///   fails fast without sending a request when it is absent.
const String cookiesEnvVar = 'BILIBILI_TEST_COOKIES';
const String folderEnvVar = 'BILIBILI_TEST_FOLDER_ID';
const String bvidEnvVar = 'BILIBILI_TEST_BVID';
const String writeFolderEnvVar = 'BILIBILI_TEST_WRITE_FOLDER_ID';
const String writeBvidEnvVar = 'BILIBILI_TEST_WRITE_BVID';

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

void main() {
  final cookieHeader = _envValue(cookiesEnvVar);
  final readOnlySkip = cookieHeader == null
      ? 'Set $cookiesEnvVar to run authenticated online checks.'
      : null;

  group('authenticated account (read-only)', skip: readOnlySkip, () {
    late BilibiliAccountManager manager;
    late BilibiliAccountInfo account;

    setUpAll(() async {
      manager = BilibiliAccountManager();
      await manager.signIn(cookieHeader!);

      final info = await manager.getCurrentAccount(forceRefresh: true);
      if (info == null) {
        fail(
          'nav accepted the cookie but reported no account; '
          'the session may have just expired.',
        );
      }
      account = info;
      printOnFailure('account mid: ${account.mid}');
    });

    tearDownAll(() async {
      await manager.dispose();
    });

    /// Folder to exercise: the explicit override, else the first created one.
    Future<int?> resolveFolderId() async {
      final explicit = _envInt(folderEnvVar);
      if (explicit != null) {
        return explicit;
      }
      final folders = await manager.client.getCreatedFavoriteFolders(
        mid: account.mid,
      );
      return folders.isEmpty ? null : folders.first.mediaId;
    }

    test('signIn yields an authenticated session', () {
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
      final info = await manager.client.getMyInfo();

      expect(info.mid, account.mid);
      expect(info.name, isNotEmpty);
    });

    test(
      'favorite folders load and the first page maps to OnlineMedia',
      () async {
        final folders = await manager.client.getCreatedFavoriteFolders(
          mid: account.mid,
        );
        for (final folder in folders) {
          expect(folder.mediaId, greaterThan(0));
          expect(folder.ownerMid, anyOf(isNull, account.mid));
        }

        final folderId = await resolveFolderId();
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
      final provider = manager.createMediaProvider();
      var bvid = _envValue(bvidEnvVar);

      if (bvid == null) {
        final folderId = await resolveFolderId();
        if (folderId == null) {
          markTestSkipped('no folder to read and $bvidEnvVar is not set');
          return;
        }
        final media = await manager.client.getAllFavoriteMedia(
          mediaId: folderId,
          maxPages: 3,
        );
        if (media.isEmpty) {
          markTestSkipped('the favorite folder has no playable item');
          return;
        }
        bvid = media.first.id.id;
      }

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
        reason: 'an authenticated session must yield at least one audio source',
      );
      // Stream URLs are credentials in URL form; never assert on them.
      expect(playback.media.id.id, bvid);
    });
  });

  final writeFolderId = _envInt(writeFolderEnvVar);
  final writeBvid = _envValue(writeBvidEnvVar);
  final writeSkip = cookieHeader == null
      ? readOnlySkip
      : (writeFolderId == null || writeBvid == null)
      ? 'Set $writeFolderEnvVar and $writeBvidEnvVar to run the mutating '
            'favorite round trip.'
      : null;

  group('authenticated favorite write round trip (opt-in)', skip: writeSkip, () {
    late BilibiliAccountManager manager;
    late int aid;

    // Assigned in setUpAll, which never runs while the group is skipped, so the
    // environment variables are guaranteed to be present here.
    late int folderId;
    late String bvid;

    setUpAll(() async {
      folderId = writeFolderId!;
      bvid = writeBvid!;

      manager = BilibiliAccountManager();
      await manager.signIn(cookieHeader!);

      // The write API takes a numeric aid, so read it from public metadata.
      final media = await manager.createMediaProvider().resolve(
        Uri.parse('https://www.bilibili.com/video/$bvid'),
      );
      final resolvedAid = media.extra['aid'];
      if (resolvedAid is! int || resolvedAid <= 0) {
        fail('could not read the numeric aid for $bvid');
      }
      aid = resolvedAid;
    });

    tearDownAll(() async {
      await manager.dispose();
    });

    test(
      'adding a favorite is visible and the original state is restored',
      () async {
        Future<bool> present() async {
          final items = await manager.client.getAllFavoriteMedia(
            mediaId: folderId,
            maxPages: 5,
          );
          return items.any((media) => media.extra['aid'] == aid);
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

        await manager.client.addFavorite(aid: aid, folderIds: <int>[folderId]);
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
  });
}
