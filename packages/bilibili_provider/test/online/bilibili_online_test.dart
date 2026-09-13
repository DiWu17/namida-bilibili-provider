@Tags(<String>['online'])
library;

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:test/test.dart';

void main() {
  test(
    'public video resolves and first DASH streams pass range validation',
    () async {
      final provider = BilibiliProvider();
      final uri = Uri.parse('https://www.bilibili.com/video/BV17xeRz9EJs/');

      final media = await provider.resolve(uri);
      expect(media.id.provider, 'bilibili');
      expect(media.id.id, 'BV17xeRz9EJs');
      expect(media.id.subId, isNotEmpty);
      expect(media.title, isNotEmpty);

      final playback = await provider.getPlayback(media.id);
      expect(playback.videoStreams, isNotEmpty);
      expect(playback.audioStreams, isNotEmpty);

      final validator = BilibiliStreamValidator();
      final videoValidation = await validator.validate(
        playback.videoStreams.first,
      );
      final audioValidation = await validator.validate(
        playback.audioStreams.first,
      );

      expect(
        videoValidation.isPlayable,
        isTrue,
        reason: videoValidation.toString(),
      );
      expect(
        audioValidation.isPlayable,
        isTrue,
        reason: audioValidation.toString(),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
