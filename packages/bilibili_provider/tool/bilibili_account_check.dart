// Manual, read-only verification of the Bilibili account layer.
//
// Usage (PowerShell; the variable lives only in this shell session):
//
//   $env:BILIBILI_TEST_COOKIES = 'SESSDATA=...; bili_jct=...; DedeUserID=...'
//   dart run tool/bilibili_account_check.dart
//   dart run tool/bilibili_account_check.dart --folder 200000001
//   dart run tool/bilibili_account_check.dart --play BV1xx411c7mD
//   dart run tool/bilibili_account_check.dart --folders-only
//
// Safety:
//
// - the cookie header is read from the environment only, and is never printed;
// - nothing is written to disk and no account state is modified;
// - stream URLs are signed credentials in URL form, so they are not printed;
// - the account layer never reads a browser profile, so the value has to be
//   supplied explicitly by the user.
import 'dart:io';

import 'package:bilibili_provider/bilibili_provider.dart';

const String _cookiesVar = 'BILIBILI_TEST_COOKIES';

Future<void> main(List<String> args) async {
  final cookieHeader = Platform.environment[_cookiesVar]?.trim();
  if (cookieHeader == null || cookieHeader.isEmpty) {
    stderr.writeln('Missing $_cookiesVar.');
    stderr.writeln(
      "PowerShell: \$env:$_cookiesVar = "
      "'SESSDATA=...; bili_jct=...; DedeUserID=...'",
    );
    stderr.writeln(
      'The value is read from the environment and is never printed.',
    );
    exitCode = 2;
    return;
  }

  final folderArg = _option(args, '--folder');
  final playArg = _option(args, '--play');
  final foldersOnly = args.contains('--folders-only');

  final manager = BilibiliAccountManager();
  try {
    final session = await manager.signIn(cookieHeader);
    stdout.writeln('signed in  : mid=${session.mid}');

    final account = await manager.getCurrentAccount(forceRefresh: true);
    if (account == null) {
      stderr.writeln(
        'nav accepted the request but reported no account; '
        'the session may have expired.',
      );
      exitCode = 1;
      return;
    }

    final cookies = BilibiliCookies.parse(cookieHeader);
    stdout.writeln('account    : mid=${account.mid} name=${account.name}');
    stdout.writeln('level      : ${account.level ?? '-'}');
    stdout.writeln(
      'following  : ${account.followingCount ?? '-'}  '
      'followers: ${account.followerCount ?? '-'}',
    );
    stdout.writeln(
      'vip badge  : ${account.isVip ? account.vipLabel ?? 'yes' : 'no'} '
      '(display only; no content is unlocked by it)',
    );
    stdout.writeln('validity   : ${manager.cookieValidity}');
    stdout.writeln(
      'csrf token : ${cookies.hasCsrfToken ? 'present' : 'missing'}'
      '${cookies.hasCsrfToken ? '' : ' -> write operations will be refused'}',
    );
    stdout.writeln('manager    : $manager');

    final folders = await manager.client.getCreatedFavoriteFolders(
      mid: account.mid,
    );
    stdout.writeln('folders    : ${folders.length}');
    for (final folder in folders) {
      stdout.writeln(
        '  ${folder.mediaId}  ${folder.isPublic ? 'public ' : 'private'}  '
        '${folder.mediaCount} item(s)  ${folder.title}',
      );
    }

    if (foldersOnly) {
      return;
    }

    final selectedFolder = folderArg == null
        ? (folders.isEmpty ? null : folders.first.mediaId)
        : int.tryParse(folderArg);
    if (selectedFolder != null) {
      final page = await manager.client.getFavoriteResources(
        mediaId: selectedFolder,
        pageSize: BilibiliAccountClient.maxFavoritePageSize,
      );
      stdout.writeln(
        'folder $selectedFolder : ${page.entries.length} entry(ies) on '
        'page ${page.page}, more=${page.hasMore}, '
        'playable=${page.media.length}, invalid=${page.entries.length - page.media.length}',
      );
      for (final media in page.media.take(5)) {
        stdout.writeln(
          '  ${media.id.id}  ${media.duration ?? '-'}  ${media.title}',
        );
      }
    }

    if (playArg != null) {
      final provider = manager.createMediaProvider();
      final media = await provider.resolve(
        Uri.parse('https://www.bilibili.com/video/$playArg'),
      );
      final playback = await provider.getPlayback(media.id);

      stdout.writeln('playback   : ${media.title}');
      stdout.writeln(
        '  video=${playback.videoStreams.length} '
        'audio=${playback.audioStreams.length} '
        'muxed=${playback.muxedStreams.length}',
      );
      if (playback.videoStreams.isNotEmpty) {
        final video = playback.videoStreams.first;
        stdout.writeln(
          '  first video: ${video.qualityLabel ?? video.qualityId} '
          '${video.width}x${video.height} ${video.codec ?? ''}',
        );
      }
      if (playback.audioStreams.isNotEmpty) {
        final audio = playback.audioStreams.first;
        stdout.writeln(
          '  first audio: ${audio.qualityLabel ?? audio.qualityId}',
        );
      }
      stdout.writeln('  stream URLs are intentionally not printed');
    }
  } on BilibiliException catch (error) {
    stderr.writeln('failed: $error');
    exitCode = 1;
  } finally {
    await manager.dispose();
  }
}

String? _option(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == name && index + 1 < args.length) {
      return args[index + 1];
    }
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}
