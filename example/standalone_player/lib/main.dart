import 'dart:async';

import 'package:bilibili_provider/bilibili_provider.dart';
import 'package:bilibili_provider/io.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:online_media_provider/online_media_provider.dart';

import 'account_ui.dart';
import 'bilibili_format.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const StandalonePlayerApp());
}

class StandalonePlayerApp extends StatelessWidget {
  const StandalonePlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bilibili Standalone Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFB7299)),
        useMaterial3: true,
      ),
      home: const PlayerScreen(),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _urlController = TextEditingController(
    text: 'https://www.bilibili.com/video/BV17xeRz9EJs/',
  );

  /// Auth provider shared by the account layer and playback, so signing in
  /// changes what both of them send.
  final BilibiliAccountAuthProvider _auth = BilibiliAccountAuthProvider();

  /// Cookie file under the per-user application data directory. Plain text, so
  /// the login dialog asks before persisting.
  late final PlainTextFileBilibiliCookieStore _fileStore =
      PlainTextFileBilibiliCookieStore();

  /// Lets the login dialog decide whether this sign-in may be persisted.
  late final ConditionalBilibiliCookieStore _cookieStore =
      ConditionalBilibiliCookieStore(_fileStore);

  late final BilibiliAccountManager _account = BilibiliAccountManager(
    authProvider: _auth,
    cookieStore: _cookieStore,
  );

  late final BilibiliProvider _provider = BilibiliProvider(auth: _auth);

  late final Player _videoPlayer;
  late final Player _audioPlayer;
  late final VideoController _videoController;

  OnlineMedia? _media;
  OnlineMediaPart? _selectedPart;
  OnlineVideoStream? _selectedVideo;
  OnlineAudioStream? _selectedAudio;
  OnlineMuxedStream? _selectedMuxed;

  List<OnlineVideoStream> _videoStreams = const <OnlineVideoStream>[];
  List<OnlineAudioStream> _audioStreams = const <OnlineAudioStream>[];

  bool _resolving = false;
  bool _loadingPlayback = false;
  bool _playing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _videoPlayer = Player();
    _audioPlayer = Player();
    _videoController = VideoController(_videoPlayer);
    unawaited(_videoPlayer.setVolume(0));
    unawaited(_audioPlayer.setVolume(100));
  }

  @override
  void dispose() {
    _urlController.dispose();
    unawaited(_videoPlayer.dispose());
    unawaited(_audioPlayer.dispose());
    unawaited(_account.dispose());
    super.dispose();
  }

  /// Picks the selected part of [media], falling back to the first part.
  static OnlineMediaPart? _partFor(OnlineMedia media) {
    if (media.parts.isEmpty) {
      return null;
    }
    return media.parts.firstWhere(
      (part) => part.id == media.id.subId,
      orElse: () => media.parts.first,
    );
  }

  Future<void> _resolve() async {
    final raw = _urlController.text.trim();
    final uri = Uri.tryParse(raw);
    if (uri == null || !_provider.canHandle(uri)) {
      setState(() {
        _error =
            'Unsupported URL. Use a BV/av video URL or a b23.tv short link.';
      });
      return;
    }

    setState(() {
      _resolving = true;
      _error = null;
      _playing = false;
    });

    try {
      final media = await _provider.resolve(uri);
      if (!mounted) {
        return;
      }
      setState(() {
        _media = media;
        _selectedPart = _partFor(media);
      });
      await _loadPlayback(media.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _resolving = false;
        });
      }
    }
  }

  /// Loads an item that came from the account layer (a favorite, for example).
  ///
  /// Favorite entries carry a BVID but no CID, so one metadata request fills in
  /// the parts before playback.
  Future<void> _playMedia(OnlineMedia item) async {
    setState(() {
      _resolving = true;
      _error = null;
      _playing = false;
    });

    try {
      final resolved = await _provider.resolveById(item.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _media = resolved;
        _selectedPart = _partFor(resolved);
        _urlController.text =
            'https://www.bilibili.com/video/${resolved.id.id}';
      });
      await _loadPlayback(resolved.id);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _resolving = false;
        });
      }
    }
  }

  Future<void> _loadPlayback(OnlineMediaId mediaId) async {
    setState(() {
      _loadingPlayback = true;
      _error = null;
    });

    try {
      final playback = await _provider.getPlayback(
        mediaId,
        options: const OnlinePlaybackOptions(allowMuxedFallback: true),
      );

      final videos = List<OnlineVideoStream>.of(playback.videoStreams)
        ..sort(_sortVideoStreams);
      final audios = List<OnlineAudioStream>.of(playback.audioStreams)
        ..sort(_sortAudioStreams);
      final muxed = List<OnlineMuxedStream>.of(playback.muxedStreams)
        ..sort(_sortMuxedStreams);

      if (!mounted) {
        return;
      }
      setState(() {
        _videoStreams = videos;
        _audioStreams = audios;
        _selectedVideo = videos.isEmpty ? null : videos.first;
        _selectedAudio = audios.isEmpty ? null : audios.first;
        _selectedMuxed = muxed.isEmpty ? null : muxed.first;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPlayback = false;
        });
      }
    }
  }

  Future<void> _onPartSelected(OnlineMediaPart? part) async {
    final media = _media;
    if (media == null || part == null) {
      return;
    }
    setState(() {
      _selectedPart = part;
    });
    await _loadPlayback(
      OnlineMediaId(provider: 'bilibili', id: media.id.id, subId: part.id),
    );
  }

  Future<void> _play() async {
    final video = _selectedVideo;
    final audio = _selectedAudio;
    final muxed = _selectedMuxed;

    try {
      if (video == null || audio == null) {
        if (muxed == null) {
          _showError('No playable video/audio streams are selected.');
          return;
        }
        await _videoPlayer.setVolume(100);
        await _videoPlayer.open(
          Media(muxed.url.toString(), httpHeaders: muxed.headers),
          play: true,
        );
        if (mounted) {
          setState(() {
            _playing = true;
          });
        }
        return;
      }

      await _videoPlayer.open(
        Media(video.url.toString(), httpHeaders: video.headers),
        play: false,
      );
      await _audioPlayer.open(
        Media(audio.url.toString(), httpHeaders: audio.headers),
        play: false,
      );
      await _videoPlayer.setVolume(0);
      await _audioPlayer.setVolume(100);
      await Future.wait(<Future<void>>[
        _videoPlayer.play(),
        _audioPlayer.play(),
      ]);
      if (mounted) {
        setState(() {
          _playing = true;
        });
      }
    } catch (error) {
      _showError('Playback failed: $error');
    }
  }

  Future<void> _pause() async {
    await Future.wait(<Future<void>>[
      _videoPlayer.pause(),
      _audioPlayer.pause(),
    ]);
    if (mounted) {
      setState(() {
        _playing = false;
      });
    }
  }

  Future<void> _seek(Duration position) async {
    await Future.wait(<Future<void>>[
      _videoPlayer.seek(position),
      _audioPlayer.seek(position),
    ]);
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final media = _media;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Bilibili Standalone Player')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            BilibiliAccountCard(
              manager: _account,
              cookieStore: _cookieStore,
              storageDescription: _fileStore.file.path,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        labelText: 'Bilibili URL',
                        hintText: 'https://www.bilibili.com/video/BV...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _resolve(),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _resolving ? null : _resolve,
                      icon: _resolving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search),
                      label: const Text('Resolve'),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
            ],
            if (media != null) ...<Widget>[
              const SizedBox(height: 12),
              _MetadataCard(media: media),
              const SizedBox(height: 12),
              _SelectionCard(
                media: media,
                selectedPart: _selectedPart,
                videoStreams: _videoStreams,
                audioStreams: _audioStreams,
                selectedVideo: _selectedVideo,
                selectedAudio: _selectedAudio,
                loading: _loadingPlayback,
                onPartChanged: _onPartSelected,
                onVideoChanged: (video) {
                  setState(() {
                    _selectedVideo = video;
                  });
                  if (_playing) {
                    unawaited(_play());
                  }
                },
                onAudioChanged: (audio) {
                  setState(() {
                    _selectedAudio = audio;
                  });
                  if (_playing) {
                    unawaited(_play());
                  }
                },
              ),
              const SizedBox(height: 12),
              _PlayerCard(
                videoController: _videoController,
                video: _selectedVideo,
                playing: _playing,
                audioPlayer: _audioPlayer,
                onPlay: _play,
                onPause: _pause,
                onSeek: _seek,
              ),
            ],
            const SizedBox(height: 12),
            BilibiliFavoritesCard(manager: _account, onPlay: _playMedia),
          ],
        ),
      ),
    );
  }

  static int _videoScore(OnlineVideoStream stream) {
    final width = stream.width ?? 0;
    final height = stream.height ?? 0;
    final quality = stream.qualityId ?? 0;
    return width * height + quality;
  }

  static int _sortVideoStreams(OnlineVideoStream a, OnlineVideoStream b) {
    return _videoScore(b).compareTo(_videoScore(a));
  }

  static int _sortAudioStreams(OnlineAudioStream a, OnlineAudioStream b) {
    final aScore = a.bitrate ?? a.qualityId ?? 0;
    final bScore = b.bitrate ?? b.qualityId ?? 0;
    return bScore.compareTo(aScore);
  }

  static int _sortMuxedStreams(OnlineMuxedStream a, OnlineMuxedStream b) {
    final aScore = a.bitrate ?? a.qualityId ?? 0;
    final bScore = b.bitrate ?? b.qualityId ?? 0;
    return bScore.compareTo(aScore);
  }
}

class _MetadataCard extends StatelessWidget {
  const _MetadataCard({required this.media});

  final OnlineMedia media;

  @override
  Widget build(BuildContext context) {
    final thumbnail = media.thumbnail;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (thumbnail != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                thumbnail.toString(),
                fit: BoxFit.cover,
                headers: const <String, String>{
                  'Referer': 'https://www.bilibili.com/',
                },
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black12,
                  child: const Center(
                    child: Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  media.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('UP: ${media.artist ?? 'unknown'}'),
                Text('Duration: ${formatDuration(media.duration)}'),
                Text('Parts: ${media.parts.length}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  const _SelectionCard({
    required this.media,
    required this.selectedPart,
    required this.videoStreams,
    required this.audioStreams,
    required this.selectedVideo,
    required this.selectedAudio,
    required this.loading,
    required this.onPartChanged,
    required this.onVideoChanged,
    required this.onAudioChanged,
  });

  final OnlineMedia media;
  final OnlineMediaPart? selectedPart;
  final List<OnlineVideoStream> videoStreams;
  final List<OnlineAudioStream> audioStreams;
  final OnlineVideoStream? selectedVideo;
  final OnlineAudioStream? selectedAudio;
  final bool loading;
  final ValueChanged<OnlineMediaPart?> onPartChanged;
  final ValueChanged<OnlineVideoStream?> onVideoChanged;
  final ValueChanged<OnlineAudioStream?> onAudioChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            DropdownButtonFormField<OnlineMediaPart>(
              initialValue: selectedPart,
              decoration: const InputDecoration(
                labelText: 'Part',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<OnlineMediaPart>>[
                for (final part in media.parts)
                  DropdownMenuItem<OnlineMediaPart>(
                    value: part,
                    child: Text(
                      'P${part.index + 1}  ${part.title}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: loading ? null : onPartChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OnlineVideoStream>(
              initialValue: selectedVideo,
              decoration: const InputDecoration(
                labelText: 'Video stream',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<OnlineVideoStream>>[
                for (final stream in videoStreams)
                  DropdownMenuItem<OnlineVideoStream>(
                    value: stream,
                    child: Text(
                      _videoLabel(stream),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: loading ? null : onVideoChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<OnlineAudioStream>(
              initialValue: selectedAudio,
              decoration: const InputDecoration(
                labelText: 'Audio stream',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<OnlineAudioStream>>[
                for (final stream in audioStreams)
                  DropdownMenuItem<OnlineAudioStream>(
                    value: stream,
                    child: Text(
                      _audioLabel(stream),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: loading ? null : onAudioChanged,
            ),
            if (loading) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }

  static String _videoLabel(OnlineVideoStream stream) {
    final resolution = stream.width == null || stream.height == null
        ? '?'
        : '${stream.width}x${stream.height}';
    final fps = stream.fps == null
        ? '?'
        : '${stream.fps!.toStringAsFixed(2)}fps';
    return '${stream.qualityLabel ?? stream.qualityId ?? '?'}  '
        '$resolution  $fps  ${stream.codec ?? '?'}';
  }

  static String _audioLabel(OnlineAudioStream stream) {
    final bitrate = stream.bitrate == null
        ? '?'
        : '${(stream.bitrate! / 1000).toStringAsFixed(0)} kbps';
    return '${stream.qualityLabel ?? stream.qualityId ?? '?'}  '
        '$bitrate  ${stream.codec ?? '?'}';
  }
}

class _PlayerCard extends StatelessWidget {
  const _PlayerCard({
    required this.videoController,
    required this.video,
    required this.playing,
    required this.audioPlayer,
    required this.onPlay,
    required this.onPause,
    required this.onSeek,
  });

  final VideoController videoController;
  final OnlineVideoStream? video;
  final bool playing;
  final Player audioPlayer;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final aspectRatio = video?.width != null && video?.height != null
        ? video!.width! / video!.height!
        : 16 / 9;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ColoredBox(
                color: Colors.black,
                child: Video(
                  controller: videoController,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  fill: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<Duration>(
              stream: audioPlayer.stream.position,
              builder: (context, snapshot) {
                final position = snapshot.data ?? Duration.zero;
                final duration = audioPlayer.state.duration;
                final max = duration.inMilliseconds <= 0
                    ? 1.0
                    : duration.inMilliseconds.toDouble();
                final value = position.inMilliseconds
                    .clamp(0, max.toInt())
                    .toDouble();
                return Column(
                  children: <Widget>[
                    Slider(
                      min: 0,
                      max: max,
                      value: value,
                      onChanged: (newValue) {
                        onSeek(Duration(milliseconds: newValue.round()));
                      },
                    ),
                    Text(
                      '${formatDuration(position)} / '
                      '${formatDuration(duration)}',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: playing ? onPause : onPlay,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  label: Text(playing ? 'PAUSE' : 'PLAY'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
