import 'package:online_media_provider/online_media_provider.dart';

import '../errors/bilibili_exception.dart';
import '../models/bilibili_api_models.dart';
import '../models/bilibili_part.dart';
import 'bilibili_api_response.dart';

/// Parses Bilibili video metadata and maps it to the provider-neutral contract.
class BilibiliMetadataParser {
  const BilibiliMetadataParser();

  /// Parses a full Bilibili `x/web-interface/view` response body.
  BilibiliVideoInfo parseVideoInfoResponse(String body) {
    final data = BilibiliApiResponse.decodeData(
      body,
      operation: 'Bilibili view API',
    );
    return parseVideoInfoData(data);
  }

  /// Parses the `data` object from `x/web-interface/view`.
  BilibiliVideoInfo parseVideoInfoData(Map<String, Object?> data) {
    final bvid = BilibiliApiResponse.asString(data['bvid']);
    if (bvid == null || bvid.isEmpty) {
      throw const BilibiliParseException(
        'Bilibili video metadata did not contain a BVID.',
      );
    }

    final parts = _parseParts(data['pages']);
    final topLevelDuration = BilibiliApiResponse.asDurationSeconds(
      data['duration'],
    );
    final fallbackDuration = parts.length == 1 ? parts.single.duration : null;

    return BilibiliVideoInfo(
      aid: BilibiliApiResponse.asInt(data['aid']) ?? 0,
      bvid: bvid,
      title: BilibiliApiResponse.asString(data['title']) ?? '',
      description: BilibiliApiResponse.asString(data['desc']),
      thumbnail: BilibiliApiResponse.asUri(data['pic']),
      duration: topLevelDuration ?? fallbackDuration,
      owner: _parseOwner(data['owner']),
      parts: parts,
    );
  }

  /// Maps internal metadata to an [OnlineMedia] value.
  ///
  /// [selectedPage] is 1-based and defaults to the first available part.
  OnlineMedia toOnlineMedia(BilibiliVideoInfo info, {int? selectedPage}) {
    final page =
        selectedPage ?? (info.parts.isEmpty ? null : info.parts.first.page);
    final selectedPart = page == null
        ? null
        : _findPartByPage(info.parts, page);

    if (page != null && selectedPart == null) {
      throw BilibiliNotFoundException(
        'Bilibili video does not contain page p=$page.',
      );
    }

    return OnlineMedia(
      id: OnlineMediaId(
        provider: 'bilibili',
        id: info.bvid,
        subId: selectedPart?.cid,
      ),
      title: info.title,
      artist: info.owner?.name,
      thumbnail: info.thumbnail,
      duration: info.duration,
      description: info.description,
      parts: <OnlineMediaPart>[
        for (final part in info.parts)
          OnlineMediaPart(
            id: part.cid,
            title: part.title,
            index: part.page - 1,
            duration: part.duration,
          ),
      ],
      extra: <String, Object?>{
        'aid': info.aid,
        if (info.owner?.mid != null) 'ownerMid': info.owner!.mid,
      },
    );
  }

  BilibiliOwner? _parseOwner(Object? rawOwner) {
    final owner = BilibiliApiResponse.asMap(rawOwner);
    if (owner == null) {
      return null;
    }
    return BilibiliOwner(
      mid: BilibiliApiResponse.asInt(owner['mid']),
      name: BilibiliApiResponse.asString(owner['name']),
      avatar: BilibiliApiResponse.asUri(owner['face']),
    );
  }

  List<BilibiliPart> _parseParts(Object? rawPages) {
    final pages = BilibiliApiResponse.asList(rawPages);
    if (pages == null || pages.isEmpty) {
      return const <BilibiliPart>[];
    }

    final parts = <BilibiliPart>[];
    for (final rawPage in pages) {
      final pageMap = BilibiliApiResponse.asMap(rawPage);
      if (pageMap == null) {
        continue;
      }

      final cid =
          BilibiliApiResponse.asString(pageMap['cid']) ??
          BilibiliApiResponse.asInt(pageMap['cid'])?.toString();
      final page = BilibiliApiResponse.asInt(pageMap['page']);
      if (cid == null || cid.isEmpty || page == null || page <= 0) {
        continue;
      }

      parts.add(
        BilibiliPart(
          cid: cid,
          page: page,
          title: BilibiliApiResponse.asString(pageMap['part']) ?? '',
          duration: BilibiliApiResponse.asDurationSeconds(pageMap['duration']),
        ),
      );
    }

    parts.sort((a, b) => a.page.compareTo(b.page));
    return List<BilibiliPart>.unmodifiable(parts);
  }

  BilibiliPart? _findPartByPage(List<BilibiliPart> parts, int page) {
    for (final part in parts) {
      if (part.page == page) {
        return part;
      }
    }
    return null;
  }
}
