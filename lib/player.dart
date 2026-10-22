import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'cast.dart';
import 'catalog.dart';
import 'quality.dart';
import 'ui_locale.dart';
import 'download_widgets.dart';
import 'library.dart';

final ValueNotifier<bool> playerFullscreenViewport = ValueNotifier(false);

/// A selectable video rendition reported by the native player.
class VideoTrack {
  const VideoTrack(
      {required this.groupIndex,
      required this.trackIndex,
      this.width = 0,
      this.height = 0,
      this.bitrate = 0,
      this.selected = false});
  final int groupIndex;
  final int trackIndex;
  final int width;
  final int height;
  final int bitrate;
  final bool selected;

  String get label => height > 0
      ? '${height}p'
      : bitrate > 0
          ? '${(bitrate / 1000000).toStringAsFixed(1)}Mbps'
          : '默认';

  static List<VideoTrack> parse(Object? value) {
    if (value is! List) return const [];
    final tracks = <VideoTrack>[];
    for (final item in value) {
      if (item is! Map) continue;
      int num0(String key) => (item[key] as num?)?.toInt() ?? 0;
      tracks.add(VideoTrack(
          groupIndex: num0('groupIndex'),
          trackIndex: num0('trackIndex'),
          width: num0('width'),
          height: num0('height'),
          bitrate: num0('bitrate'),
          selected: item['selected'] == true));
    }
    tracks.sort((a, b) => b.height.compareTo(a.height));
    return tracks;
  }
}

Episode? nextEpisodeOnLine(
    Map<String, List<Episode>> lines, String? line, Episode? current) {
  final episodes = lines[line];
  if (episodes == null || current == null) return null;
  final index = episodes.indexWhere((item) => item.url == current.url);
  return index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
}

Episode? previousEpisodeOnLine(
    Map<String, List<Episode>> lines, String? line, Episode? current) {
  final episodes = lines[line];
  if (episodes == null || current == null) return null;
  final index = episodes.indexWhere((item) => item.url == current.url);
  return index > 0 ? episodes[index - 1] : null;
}

int scrubPositionMs(int startMs, double distance, int durationMs) =>
    (startMs + (distance * 1000).round()).clamp(0, durationMs);

/// Channel names, argument names and event keys are supported by recovered
/// g1/b.java + g1/f.java. The implementation on Android is newly written.
class MediaController {
  MediaController()
      : playerId = DateTime.now().microsecondsSinceEpoch,
        events = const EventChannel('flutter_player_av/events');

  static const MethodChannel methods =
      MethodChannel('flutter_player_av/methods');
  final int playerId;
  final EventChannel events;

  Stream<Map<dynamic, dynamic>> listen() => events
      .receiveBroadcastStream()
      .where((event) => event is Map && event['playerId'] == playerId)
      .cast<Map<dynamic, dynamic>>();

  Future<void> call(String name,
      [Map<String, Object?> extra = const {}]) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw UnsupportedError('播放器仅在 Android 上提供');
    }
    await methods.invokeMethod<void>(name, {'playerId': playerId, ...extra});
  }

  Future<void> open(String url,
      {int startMs = 0,
      Map<String, String> headers = const {},
      bool allowCleartext = false}) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        (parsed.scheme != 'https' &&
            !(allowCleartext && parsed.scheme == 'http'))) {
      throw const FormatException('只播放 HTTPS 媒体或已下载文件');
    }
    await call('open',
        {'url': url, 'startMs': startMs, 'headers': headers, 'play': true});
  }

  Future<void> openFile(String path, {int startMs = 0}) =>
      call('open', {'filePath': path, 'startMs': startMs, 'play': true});
  Future<void> openDownload(String id, {int startMs = 0}) => call(
      'openDownload', {'downloadId': id, 'startMs': startMs, 'play': true});
  Future<void> pause() => call('pause');
  Future<void> play() => call('play');
  Future<void> seek(int ms) => call('seek', {'positionMs': ms});
  Future<void> setRate(double rate) => call('setRate', {'rate': rate});
  Future<void> setTrack(VideoTrack? track) => call('setTrack', {
        'groupIndex': track?.groupIndex ?? -1,
        'trackIndex': track?.trackIndex ?? -1
      });
  Future<void> dispose() => call('dispose');

  /// True on Android TV / leanback devices. Used to gate TV-only behavior
  /// (e.g. stealing focus on page entry) without a repeated channel call.
  static final Future<bool> isTelevision = _detectTelevision();

  static Future<bool> _detectTelevision() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      return await methods
              .invokeMethod<bool>('isTv', {'playerId': 0}) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// System media volume for remote volume keys. Global (no playerId).
  static Future<void> adjustVolume(int direction) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future.value();
    }
    return methods
        .invokeMethod<void>('volume', {'direction': direction, 'playerId': 0});
  }

  Widget videoView() => AndroidView(
        viewType: 'flutter_player_av/player_view',
        creationParams: {'playerId': playerId},
        creationParamsCodec: const StandardMessageCodec(),
      );
}

class PlayerPage extends StatefulWidget {
  const PlayerPage(
      {super.key,
      required this.entry,
      required this.library,
      this.initial,
      this.initialPositionMs,
      this.preferOffline = false,
      this.originalEntry,
      this.onOpenOriginal,
      this.embedded = false,
      this.onChooseSource,
      this.onShowDetails,
      this.onPlaybackChanged,
      this.onPlaybackError,
      this.headers = const {},
      this.live = false});
  final MediaEntry entry;
  final Library library;
  final Episode? initial;
  final int? initialPositionMs;
  final bool preferOffline;
  final MediaEntry? originalEntry;
  final Future<void> Function()? onOpenOriginal;
  final bool embedded;
  final VoidCallback? onChooseSource;
  final VoidCallback? onShowDetails;
  final void Function(Episode episode, int positionMs)? onPlaybackChanged;

  /// Fired on asynchronous playback errors so hosts can react (e.g. the
  /// detail page falling back to another source). Live mode zaps channels
  /// internally and does not call this until it gives up.
  final VoidCallback? onPlaybackError;
  final Map<String, String> headers;

  /// Live streams have no meaningful progress to persist and cannot be
  /// downloaded for offline playback.
  final bool live;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final MediaController controller = MediaController();
  Completer<void>? _selectionCompleted;
  StreamSubscription<Map<dynamic, dynamic>>? subscription;
  String? line;
  Episode? episode;
  bool ready = false;
  bool playing = false;
  bool loading = false;
  bool selecting = false;
  String? error;
  int positionMs = 0;
  int durationMs = 0;
  double rate = 1;
  final ValueNotifier<int> _repaintFullscreen = ValueNotifier(0);
  Timer? _controlsTimer;
  Timer? _autoNextTimer;
  int _autoNextSeconds = 0;
  bool _completionArmed = false;
  bool _checkingResume = false;
  bool _restoringCompleted = false;
  int _lastSavedPositionMs = 0;
  int _requestedStartMs = 0;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _completed = false;
  bool _holdingFast = false;
  bool _holdActive = false;
  double _holdStartX = 0;
  int _holdStartMs = 0;
  int? _scrubMs;
  List<VideoTrack> videoTracks = const [];
  VideoTrack? _manualTrack;
  // Separate nodes per surface: the embedded and fullscreen players are
  // both alive during fullscreen, and a shared node attaches to whichever
  // widget built last — focus could land on the offstage embedded copy.
  final FocusNode _surfaceFocus = FocusNode(debugLabel: 'video-surface');
  final FocusNode _embeddedFocus = FocusNode(debugLabel: 'embedded-surface');
  final FocusNode _playFocus = FocusNode(debugLabel: 'play-button');

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _repaintFullscreen.value++;
  }

  void _showControls() {
    _controlsTimer?.cancel();
    _controlsVisible = true;
    _refresh();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !playing || _holdActive || _scrubMs != null) return;
      _controlsVisible = false;
      if (_fullscreen) _surfaceFocus.requestFocus();
      _refresh();
    });
  }

  /// Remote back key (or remote wake) in fullscreen: bring the overlay up
  /// and hand focus to the play button for arrow navigation.
  void _wakeControls() {
    _showControls();
    if (_fullscreen) {
      // The overlay buttons only exist after this frame builds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controlsVisible) _playFocus.requestFocus();
      });
    }
  }

  void _hideControls() {
    _controlsTimer?.cancel();
    _controlsVisible = false;
    if (_fullscreen) _surfaceFocus.requestFocus();
    _refresh();
  }

  @override
  void initState() {
    super.initState();
    widget.library.addListener(_libraryChanged);
    final initial =
        widget.initial ?? widget.library.lastWatchedEpisode(widget.entry);
    for (final group in widget.entry.lines.entries) {
      if (group.value.isNotEmpty) {
        line ??= group.key;
        episode ??= group.value.first;
        if (initial != null &&
            group.value.any((item) => item.url == initial.url)) {
          line = group.key;
          episode = initial;
          break;
        }
      }
    }
    _initialize();
  }

  @override
  void didUpdateWidget(covariant PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.library, widget.library)) {
      oldWidget.library.removeListener(_libraryChanged);
      widget.library.addListener(_libraryChanged);
    }
    if (identical(oldWidget.entry, widget.entry)) return;
    _cancelAutoNext();
    if (episode != null && positionMs > 0 && !oldWidget.live) {
      unawaited(oldWidget.library
          .recordPlay(oldWidget.originalEntry ?? oldWidget.entry,
              episode: episode,
              position: _checkingResume ? null : positionMs,
              duration: durationMs,
              completed: _restoringCompleted || _completed
                  ? true
                  : _checkingResume
                      ? null
                      : false)
          .catchError((Object _) {}));
    }
    final entry = widget.entry;
    final selectedLine = entry.lines.entries.firstWhere(
        (group) => group.value.any((item) => item.url == widget.initial?.url),
        orElse: () => entry.lines.entries.first);
    final next = widget.initial ?? selectedLine.value.first;
    final startMs = widget.initialPositionMs ?? 0;
    line = selectedLine.key;
    episode = ready ? null : next;
    positionMs = 0;
    durationMs = 0;
    if (ready) error = null;
    _completed = false;
    _completionArmed = false;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final selection = _selectionCompleted?.future;
      if (selection != null) await selection;
      if (!mounted || !identical(widget.entry, entry)) return;
      await _select(next, startMs: startMs);
      if (mounted) _showControls();
    });
  }

  Future<void> _initialize() async {
    try {
      await controller.call('create');
      if (!mounted) {
        await controller.dispose();
        return;
      }
      subscription = controller.listen().listen(_event);
      setState(() => ready = true);
      await _select(episode, startMs: widget.initialPositionMs);
    } catch (_) {
      if (mounted) setState(() => error = '无法初始化 Android 播放器');
    }
  }

  void _event(Map<dynamic, dynamic> event) {
    if (!mounted) return;
    if (event['type'] == 'completed' && event['value'] == true) {
      if (selecting ||
          _checkingResume ||
          _restoringCompleted ||
          !_completionArmed ||
          _completed) {
        return;
      }
      _finishEpisode();
      return;
    }
    setState(() {
      switch (event['type']) {
        case 'playing':
          playing = !_completed && event['value'] == true;
          if (_completed && event['value'] == true) {
            unawaited(_pauseCompleted());
          }
        case 'buffering':
          loading = event['value'] == true;
        case 'position':
          final value = event['value'];
          if (value is num &&
              _scrubMs == null &&
              !_completed &&
              (!_checkingResume || value >= _requestedStartMs - 1000)) {
            positionMs = value.toInt();
            if (_checkingResume && durationMs > 0) _checkingResume = false;
          }
          if (!selecting &&
              !_completed &&
              !_checkingResume &&
              !_restoringCompleted &&
              positionMs > 0 &&
              positionMs < durationMs) {
            _completionArmed = true;
          }
        case 'duration':
          final value = event['value'];
          if (value is num) durationMs = value.toInt();
          if (_completed && durationMs > 0) positionMs = durationMs;
        case 'tracks':
          final parsed = VideoTrack.parse(event['value']);
          videoTracks = parsed;
          final manual = _manualTrack;
          if (manual != null &&
              !parsed.any((track) =>
                  track.groupIndex == manual.groupIndex &&
                  track.trackIndex == manual.trackIndex)) {
            _manualTrack = null;
          }
        case 'error':
          // Public IPTV streams die often: auto-zap to the next channel
          // instead of leaving the user on an error screen. Capped.
          if (widget.live &&
              !selecting &&
              episode != null &&
              ++_liveFailStreak < 6) {
            _switchChannel(1);
          } else {
            error = '播放失败，请检查地址、格式和网络';
            if (!widget.live) widget.onPlaybackError?.call();
          }
      }
    });
    if (event['type'] == 'duration' && _checkingResume && durationMs > 0) {
      if (_requestedStartMs >= durationMs) {
        _restoringCompleted = true;
        if (!selecting) _finishEpisode();
      } else if (positionMs >= _requestedStartMs - 1000) {
        _checkingResume = false;
      }
    }
    if (event['type'] == 'error') _cancelAutoNext();
    _repaintFullscreen.value++;
    if (event['type'] == 'playing') {
      _liveFailStreak = 0;
      if (!playing && _holdActive) _holdEnd(commit: false);
      if (!playing && !selecting) unawaited(_saveProgress());
      // Only refresh the auto-hide timer — a quiet remote seek ends in a
      // 'playing' event and must not resurrect hidden controls.
      if (_controlsVisible) _showControls();
    }
    if (event['type'] == 'position' &&
        !selecting &&
        !_checkingResume &&
        !_restoringCompleted &&
        !_completed &&
        (positionMs - _lastSavedPositionMs).abs() >= 5000) {
      unawaited(_saveProgress());
    }
    if (event['type'] == 'duration' && _completed) unawaited(_saveProgress());
    if (episode != null) widget.onPlaybackChanged?.call(episode!, positionMs);
  }

  Future<void> _saveProgress() async {
    if (widget.live) return;
    _lastSavedPositionMs = positionMs;
    try {
      await widget.library.recordPlay(widget.originalEntry ?? widget.entry,
          episode: episode,
          position: _checkingResume ? null : positionMs,
          duration: durationMs,
          completed: _restoringCompleted || _completed
              ? true
              : _checkingResume
                  ? null
                  : false);
    } catch (_) {
      // A persistence failure must not interrupt playback.
    }
  }

  Future<void> _pauseCompleted() async {
    try {
      await controller.pause();
    } catch (_) {}
  }

  void _finishEpisode() {
    if (_completed) return;
    _restoringCompleted = false;
    _checkingResume = false;
    _completed = true;
    playing = false;
    if (durationMs > 0) positionMs = durationMs;
    unawaited(_pauseCompleted());
    unawaited(_saveProgress());
    if (episode != null) widget.onPlaybackChanged?.call(episode!, positionMs);
    if (widget.library.autoPlayNext &&
        nextEpisodeOnLine(widget.entry.lines, line, episode) != null) {
      _autoNextSeconds = 3;
      _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !widget.library.autoPlayNext) {
          _cancelAutoNext();
          return;
        }
        _autoNextSeconds--;
        if (_autoNextSeconds == 0) {
          _cancelAutoNext();
          unawaited(_playNext());
        } else {
          _refresh();
        }
      });
    }
    _showControls();
  }

  Future<void> _playNext() async {
    if (selecting || !mounted || !_completed || !widget.library.autoPlayNext) {
      return;
    }
    final next = nextEpisodeOnLine(widget.entry.lines, line, episode);
    if (next == null) {
      _completed = true;
      _showControls();
      return;
    }
    await _select(next, startMs: 0);
  }

  void _cancelAutoNext({bool refresh = true}) {
    _autoNextTimer?.cancel();
    _autoNextTimer = null;
    final visible = _autoNextSeconds > 0;
    _autoNextSeconds = 0;
    if (refresh && visible) _refresh();
  }

  void _libraryChanged() {
    if (!widget.library.autoPlayNext) _cancelAutoNext();
  }

  Future<void> _select(Episode? next,
      {bool local = false, int? startMs}) async {
    if (next == null || !ready || selecting) return;
    _cancelAutoNext();
    final completed = Completer<void>();
    _selectionCompleted = completed;
    setState(() => selecting = true);
    _repaintFullscreen.value++;
    try {
      await _openEpisode(next, local: local, startMs: startMs);
    } finally {
      completed.complete();
      if (identical(_selectionCompleted, completed)) _selectionCompleted = null;
      if (mounted) {
        setState(() => selecting = false);
        _repaintFullscreen.value++;
        if (_restoringCompleted && error == null) _finishEpisode();
      }
    }
  }

  Future<void> _openEpisode(Episode next,
      {bool local = false, int? startMs}) async {
    if (episode != null && positionMs > 0 && episode!.url != next.url) {
      await _saveProgress();
    }
    if (!mounted) return;
    setState(() {
      episode = next;
      error = null;
      positionMs = 0;
      durationMs = 0;
      _completed = false;
      _completionArmed = false;
      _restoringCompleted =
          widget.library.watchProgress(widget.entry.id, next).completed;
      if (_restoringCompleted) {
        durationMs =
            widget.library.watchProgress(widget.entry.id, next).durationMs;
      }
      _lastSavedPositionMs = 0;
      _scrubMs = null;
      videoTracks = const [];
      _manualTrack = null;
    });
    _requestedStartMs = _restoringCompleted && durationMs > 0
        ? durationMs
        : startMs ?? widget.library.resumePosition(widget.entry.id, next);
    _checkingResume = _requestedStartMs > 0 && !_restoringCompleted;
    _repaintFullscreen.value++;
    widget.onPlaybackChanged?.call(next, startMs ?? 0);
    try {
      if (local || widget.preferOffline) {
        final path = widget.library.downloadedFile(widget.entry.id, next);
        if (path == null) throw const FormatException('没有该集的已下载文件');
        final position = _requestedStartMs;
        if (path.startsWith('media3:')) {
          await controller.openDownload(path.substring(7), startMs: position);
        } else {
          await controller.openFile(path, startMs: position);
        }
      } else {
        await controller.open(next.url,
            startMs: _requestedStartMs,
            headers: widget.headers,
            allowCleartext: widget.live);
      }
      _liveFailStreak = 0;
      try {
        if (!widget.live) {
          await widget.library
              .recordPlay(widget.originalEntry ?? widget.entry, episode: next);
        }
      } catch (_) {}
    } catch (_) {
      if (!mounted) return;
      // Public IPTV streams die often: hop to the next channel instead of
      // leaving the user on an error screen. Capped to avoid endless zapping.
      if (widget.live && ++_liveFailStreak < 6) {
        _switchChannel(1);
      } else {
        setState(() => error = '播放地址不可用');
      }
    }
  }

  int _liveFailStreak = 0;

  Future<String?> _resolveDownloadUrl(Episode target) {
    final selected = _manualTrack;
    if (selected == null || target.url != episode?.url) {
      return Future.value();
    }
    return variantUrlForHeight(target.url, selected.height,
        headers: widget.headers);
  }

  Future<void> _download() async {
    _cancelAutoNext();
    await _saveProgress();
    if (!mounted) return;
    final viewDownloads = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DownloadEpisodeSheet(
            entry: widget.entry,
            episodes: widget.entry.lines[line] ?? const [],
            current: episode,
            library: widget.library,
            headers: widget.headers,
            resolveDownloadUrl: _resolveDownloadUrl));
    if (viewDownloads != true || !mounted) return;
    final resume = playing;
    if (resume) await controller.pause();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DownloadsPage(library: widget.library)));
    if (mounted && resume) await controller.play();
  }

  Future<void> _openOriginal() async {
    _cancelAutoNext();
    await _saveProgress();
    final resume = playing;
    if (resume) await controller.pause();
    if (!mounted) return;
    await widget.onOpenOriginal?.call();
    if (mounted && resume) await controller.play();
  }

  Future<void> _castTo(CastDevice device) async {
    final current = episode;
    if (current == null) return;
    try {
      await CastClient.cast(device,
          url: current.url,
          title: '${widget.entry.title} · ${current.name}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: LocalizedText('已推送到 ${device.name}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: LocalizedText('投屏失败，请重试')));
      }
    }
  }

  Future<void> _showCastPicker() => showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => _CastSheet(onPicked: (device) {
            Navigator.of(sheet).pop();
            unawaited(_castTo(device));
          }));

  Future<void> _showAllEpisodes() => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => AnimatedBuilder(
          animation: _repaintFullscreen,
          builder: (_, child) => _EpisodeSheet(
              episodes: widget.entry.lines[line] ?? const [],
              selectedUrl: episode?.url,
              enabled: ready && !selecting,
              onSelected: (next) {
                Navigator.of(sheet).pop();
                unawaited(_select(next));
              })));

  @override
  void dispose() {
    _cancelAutoNext(refresh: false);
    widget.library.removeListener(_libraryChanged);
    _controlsTimer?.cancel();
    if (_fullscreen) playerFullscreenViewport.value = false;
    subscription?.cancel();
    _surfaceFocus.dispose();
    _embeddedFocus.dispose();
    _playFocus.dispose();
    if (ready) {
      unawaited(_saveProgress());
      controller.dispose();
    }
    _repaintFullscreen.dispose();
    super.dispose();
  }

  String _time(int ms) {
    final seconds = (ms / 1000).floor().clamp(0, 359999);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _seek(int ms) async {
    if (!ready || durationMs <= 0) return;
    _cancelAutoNext();
    final target = ms.clamp(0, durationMs);
    setState(() {
      positionMs = target;
      _completed = false;
      _completionArmed = false;
      _restoringCompleted = false;
      _checkingResume = false;
    });
    _repaintFullscreen.value++;
    if (episode != null) widget.onPlaybackChanged?.call(episode!, target);
    try {
      await controller.seek(target);
      await _saveProgress();
    } catch (_) {
      if (mounted) setState(() => error = '无法调整播放进度');
    }
  }

  Future<void> _changeRate(double nextRate, {bool temporary = false}) async {
    try {
      await controller.setRate(nextRate);
      if (mounted) {
        setState(() {
          if (!temporary) rate = nextRate;
        });
        _repaintFullscreen.value++;
      }
    } catch (_) {
      if (mounted) setState(() => error = '无法切换播放速度');
    }
  }

  Future<void> _changeQuality(VideoTrack? track) async {
    try {
      await controller.setTrack(track);
      if (mounted) {
        setState(() => _manualTrack = track);
        _repaintFullscreen.value++;
      }
    } catch (_) {
      if (mounted) setState(() => error = '无法切换清晰度');
    }
  }

  Future<void> _togglePlayback() async {
    _cancelAutoNext();
    try {
      if (playing) {
        await controller.pause();
      } else {
        if (_completed) await _seek(0);
        await controller.play();
      }
    } catch (_) {
      if (mounted) setState(() => error = '无法继续播放');
    }
  }

  void _changeLine(String nextLine) {
    if (selecting || nextLine == line) return;
    final lines = widget.entry.lines;
    final target =
        Episode.onLine(lines[nextLine] ?? [], episode, lines[line] ?? []);
    if (target == null) return;
    final matches = target.name.trim() == episode?.name.trim() ||
        (Episode.ordinal(target.name) != null &&
            Episode.ordinal(target.name) ==
                Episode.ordinal(episode?.name ?? ''));
    final startMs = matches && !_completed ? positionMs : 0;
    setState(() {
      line = nextLine;
      if (!ready) episode = target;
    });
    _repaintFullscreen.value++;
    if (ready) unawaited(_select(target, startMs: startMs));
  }

  void _tapVideo(TapUpDetails details, double width) {
    if (widget.live && episode != null && !selecting) {
      if (details.localPosition.dx < width * 0.25) {
        _switchChannel(-1);
        return;
      }
      if (details.localPosition.dx > width * 0.75) {
        _switchChannel(1);
        return;
      }
    }
    _tapVideoToggle();
  }

  /// Live channel zap: cycles through the channel list (episodes of the
  /// '直播' line) with wrap-around. Only reached in live mode.
  void _switchChannel(int delta) {
    final episodes = widget.entry.lines[line];
    if (episodes == null || episodes.length < 2 || episode == null) return;
    final index = episodes.indexWhere((item) => item.url == episode!.url);
    if (index < 0) return;
    unawaited(_select(
        episodes[(index + delta + episodes.length) % episodes.length]));
  }

  void _holdStart(LongPressStartDetails details, double width) {
    if (widget.live) return;
    _holdActive = true;
    _holdStartX = details.localPosition.dx;
    _holdStartMs = positionMs;
    if (ready && !selecting && details.localPosition.dx > width / 2) {
      _holdingFast = true;
      unawaited(_changeRate(2, temporary: true));
    }
    _showControls();
  }

  void _holdMove(LongPressMoveUpdateDetails details) {
    if (!_holdActive || !ready || durationMs <= 0) return;
    final distance = details.localPosition.dx - _holdStartX;
    if (_scrubMs == null && distance.abs() < 12) return;
    _scrubMs = scrubPositionMs(_holdStartMs, distance, durationMs);
    _refresh();
  }

  void _holdEnd({bool commit = true}) {
    if (!_holdActive) return;
    _holdActive = false;
    if (_holdingFast) {
      _holdingFast = false;
      unawaited(_changeRate(rate, temporary: true));
    }
    final target = _scrubMs;
    _scrubMs = null;
    if (commit && target != null) unawaited(_seek(target));
    _showControls();
  }

  Future<void>? _fullscreenSession;

  Future<void> _enterFullscreen() {
    if (_fullscreenSession != null) return _fullscreenSession!;
    final session = _showFullscreen();
    _fullscreenSession = session;
    return session.whenComplete(() => _fullscreenSession = null);
  }

  Future<void> _showFullscreen() async {
    if (_fullscreen || !ready) return;
    setState(() => _fullscreen = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    playerFullscreenViewport.value = true;
    try {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _FullscreenPlayer(player: this)));
    } finally {
      if (mounted) _holdEnd(commit: false);
      playerFullscreenViewport.value = false;
      await SystemChrome.setPreferredOrientations([]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (mounted) setState(() => _fullscreen = false);
      // Returning from fullscreen should land the remote back on the video
      // so another OK press re-enters it without re-navigating the page.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _embeddedFocus.requestFocus();
      });
    }
  }

  Future<void> _showDetails() async {
    if (_fullscreen) {
      Navigator.of(context).pop();
      await _fullscreenSession;
    }
    if (mounted) widget.onShowDetails?.call();
  }

  Future<void> _chooseSource() async {
    _cancelAutoNext();
    if (mounted) widget.onChooseSource?.call();
  }

  void _explainSingleLine() => ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: LocalizedText('当前只有一条播放线路；可点右侧“换源”查找其他来源')));

  Widget _overlayButton(
          String tooltip, IconData icon, VoidCallback? onPressed,
          {FocusNode? focusNode}) =>
      IconButton(
        focusNode: focusNode,
        // Strong fill so the focused overlay button is unmistakable on
        // the dark control bar (the default 40% tint is nearly invisible).
        focusColor: const Color(0xE6FF7A00),
        tooltip: uiText(context, tooltip),
        icon: Icon(icon,
            size: 21, color: onPressed == null ? Colors.white38 : Colors.white),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      );

  Widget _videoSurface({required bool fullscreen}) {
    final lines = widget.entry.lines;
    final next = nextEpisodeOnLine(lines, line, episode);
    final progress = _scrubMs ?? positionMs;
    return _SurfaceFocus(
        node: fullscreen ? _surfaceFocus : _embeddedFocus,
        // Always grab initial focus: gives TVs a D-pad starting point on
        // the detail page and on entering fullscreen; invisible on touch.
        autofocus: true,
        onKey: (event) => _onSurfaceKey(event, fullscreen: fullscreen),
        child: LayoutBuilder(builder: (context, constraints) {
      return Stack(fit: StackFit.expand, children: [
        const ColoredBox(color: Colors.black),
        if (ready) controller.videoView(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => _tapVideo(details, constraints.maxWidth),
          onLongPressStart: (details) =>
              _holdStart(details, constraints.maxWidth),
          onLongPressMoveUpdate: _holdMove,
          onLongPressEnd: (_) => _holdEnd(),
          onLongPressCancel: () => _holdEnd(commit: false),
        ),
        if (!ready && error == null)
          const Center(child: CircularProgressIndicator()),
        if (loading) const Center(child: CircularProgressIndicator()),
        if (error != null)
          Center(
              child: LocalizedText(error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center)),
        if (_completed)
          Center(
              child: LocalizedText(next == null ? '本线路已播完' : '本集已播完',
                  style: const TextStyle(color: Colors.white))),
        if (_holdingFast || _scrubMs != null)
          Center(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8)),
                  child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: LocalizedText(
                          _scrubMs != null
                              ? '${_time(progress)} / ${_time(durationMs)}'
                              : '长按 2.0x 播放',
                          style: const TextStyle(color: Colors.white))))),
        if (_autoNextSeconds > 0)
          Positioned(
              left: 8,
              right: 8,
              bottom: 62,
              child: Center(
                  child: Material(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                          padding: const EdgeInsets.only(left: 10, right: 4),
                          child: Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                LocalizedText('$_autoNextSeconds 秒后播放下一集',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12)),
                                TextButton(
                                    onPressed: _cancelAutoNext,
                                    child: const LocalizedText('取消续播')),
                              ]))))),
        if (_controlsVisible) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Focus(
              // Above the top bar there is nothing — ↑ returns focus to the
              // video so arrows resume seek/volume instead of dead-ending.
              // canRequestFocus keeps the wrapper itself out of traversal.
              canRequestFocus: false,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowUp) {
                  _surfaceFocus.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent]),
              ),
              child: Row(children: [
                if (fullscreen)
                  _overlayButton('退出全屏', Icons.arrow_back,
                      () => Navigator.of(context).pop()),
                Expanded(
                    child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                            [widget.entry.title, episode?.name ?? '']
                                .where((value) => value.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white)))),
                if (lines.length > 1)
                  PopupMenuButton<String>(
                    tooltip: uiText(context, '切换线路'),
                    enabled: !selecting,
                    onSelected: _changeLine,
                    itemBuilder: (_) => [
                      for (final name in lines.keys)
                        PopupMenuItem(value: name, child: Text(name))
                    ],
                    child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.swap_horiz, color: Colors.white)),
                  )
                else
                  _overlayButton('仅一条线路', Icons.swap_horiz,
                      lines.isEmpty ? null : _explainSingleLine),
                _overlayButton(
                    '选集',
                    Icons.video_library_outlined,
                    ready && !selecting && line != null
                        ? () => unawaited(_showAllEpisodes())
                        : null),
                if (widget.onChooseSource != null)
                  _overlayButton('换源', Icons.movie_filter_outlined,
                      () => unawaited(_chooseSource())),
                _overlayButton('投屏', Icons.cast_outlined,
                    episode == null ? null : () => unawaited(_showCastPicker())),
                // Portrait keeps its dedicated 下载剧集 row below the video;
                // the overlay button only exists for fullscreen.
                if (fullscreen)
                  _overlayButton('下载剧集', Icons.download_outlined,
                      episode == null || widget.live ? null : _download),
                AnimatedBuilder(
                    animation: widget.library,
                    builder: (_, __) => _overlayButton(
                        widget.library.isFavorite(widget.entry) ? '取消收藏' : '收藏',
                        widget.library.isFavorite(widget.entry)
                            ? Icons.star
                            : Icons.star_outline,
                        () => widget.library.toggleFavorite(widget.entry))),
                if (widget.onShowDetails != null)
                  _overlayButton('详情介绍', Icons.info_outline,
                      () => unawaited(_showDetails())),
              ]),
            )),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Focus(
              // Below the bottom controls there is nothing — ↓ returns focus
              // to the video so arrows resume seek/volume.
              canRequestFocus: false,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  _surfaceFocus.requestFocus();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87]),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (!widget.live)
                  SizedBox(
                    height: 26,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5)),
                      child: Slider(
                        value: progress
                            .clamp(0, durationMs > 0 ? durationMs : 1)
                            .toDouble(),
                        max: (durationMs > 0 ? durationMs : 1).toDouble(),
                        onChanged: durationMs <= 0 || !ready
                            ? null
                            : (value) {
                                _scrubMs = value.toInt();
                                _refresh();
                              },
                        onChangeEnd: durationMs <= 0 || !ready
                            ? null
                            : (value) {
                                _scrubMs = null;
                                unawaited(_seek(value.toInt()));
                                _showControls();
                              },
                      ),
                    ),
                  ),
                  Row(children: [
                    _overlayButton(
                        widget.live ? '上一个频道' : '播放上一集',
                        Icons.skip_previous,
                        ready &&
                                !selecting &&
                                (widget.live
                                    ? (lines[line]?.length ?? 0) > 1
                                    : previousEpisodeOnLine(
                                            lines, line, episode) !=
                                        null)
                            ? () => widget.live
                                ? _switchChannel(-1)
                                : unawaited(_select(
                                    previousEpisodeOnLine(lines, line, episode),
                                    startMs: 0))
                            : null),
                    _overlayButton(
                        playing ? '暂停' : (_completed ? '重播' : '播放'),
                        playing ? Icons.pause : Icons.play_arrow,
                        ready ? () => unawaited(_togglePlayback()) : null,
                        focusNode: fullscreen ? _playFocus : null),
                    Expanded(
                        child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: widget.live
                                ? const Row(mainAxisSize: MainAxisSize.min,
                                    children: [
                                        Icon(Icons.circle,
                                            size: 8, color: Colors.redAccent),
                                        SizedBox(width: 4),
                                        LocalizedText('直播',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11)),
                                      ])
                                : LocalizedText(
                                    '${_time(progress)} / ${_time(durationMs)}',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11)))),
                    _overlayButton(
                        widget.live ? '下一个频道' : '播放下一集',
                        Icons.skip_next,
                        ready &&
                                !selecting &&
                                (widget.live
                                    ? (lines[line]?.length ?? 0) > 1
                                    : next != null)
                            ? () => widget.live
                                ? _switchChannel(1)
                                : unawaited(_select(next, startMs: 0))
                            : null),
                    if (videoTracks.isNotEmpty)
                      PopupMenuButton<Object?>(
                        tooltip: uiText(context, '清晰度'),
                        enabled: ready && !selecting,
                        onSelected: (value) => unawaited(
                            _changeQuality(value is VideoTrack ? value : null)),
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem(
                              value: 'auto',
                              checked: _manualTrack == null,
                              child: const LocalizedText('自动')),
                          for (final track in videoTracks)
                            CheckedPopupMenuItem(
                                value: track,
                                checked: track.groupIndex ==
                                        _manualTrack?.groupIndex &&
                                    track.trackIndex ==
                                        _manualTrack?.trackIndex,
                                child: Text(track.bitrate > 0
                                    ? '${track.label} · ${(track.bitrate / 1000000).toStringAsFixed(1)}Mbps'
                                    : track.label)),
                        ],
                        child: SizedBox(
                            width: 48,
                            height: 36,
                            child: Center(
                                child: Text(
                                    _manualTrack?.label ??
                                        (videoTracks.length == 1
                                            ? videoTracks.first.label
                                            : '自动'),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11)))),
                      ),
                    if (!widget.live)
                    PopupMenuButton<double>(
                      tooltip: uiText(context, '倍速'),
                      enabled: ready,
                      initialValue: rate,
                      onSelected: (value) => unawaited(_changeRate(value)),
                      itemBuilder: (_) => [
                        for (final value in [0.5, 1.0, 1.25, 1.5, 2.0, 3.0])
                          PopupMenuItem(
                              value: value, child: LocalizedText('${value}x')),
                      ],
                      child: SizedBox(
                          width: 42,
                          height: 36,
                          child: Center(
                              child: LocalizedText('${rate}x',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 11)))),
                    ),
                    _overlayButton(
                        fullscreen ? '退出全屏' : '全屏',
                        fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        ready
                            ? fullscreen
                                ? () => Navigator.of(context).pop()
                                : () => unawaited(_enterFullscreen())
                            : null),
                  ]),
                ]))),
          ),
        ],
      ]);
    }));
  }

  /// Remote/D-pad handling scoped to the video surface.
  ///
  /// - Portrait/embedded: arrows are NOT consumed so focus traversal keeps
  ///   working (up reaches the app bar, down reaches episode/source rows);
  ///   OK on the surface jumps straight into fullscreen playback.
  /// - Fullscreen with the overlay hidden: left/right seek (or zap live
  ///   channels), up/down adjust system volume, OK toggles play/pause.
  /// - Fullscreen with the overlay visible: every key is ignored so the
  ///   overlay buttons receive traversal and activation themselves.
  // Held-arrow seek acceleration: the first press steps 10s, each repeat
  // steps further (15s, 20s, ... capped at 60s) so long videos stay
  // navigable. Resets on key-up, direction change, or entering button mode.
  int _seekRepeat = 0;
  LogicalKeyboardKey? _seekHeldKey;

  int _seekStepFor(KeyEvent event, LogicalKeyboardKey key) {
    if (event is KeyDownEvent || _seekHeldKey != key) {
      _seekRepeat = 0;
      _seekHeldKey = key;
      return 10000;
    }
    _seekRepeat++;
    return (10000 + _seekRepeat * 5000).clamp(10000, 60000);
  }

  KeyEventResult _onSurfaceKey(KeyEvent event, {required bool fullscreen}) {
    if (event is KeyUpEvent) {
      if (event.logicalKey == _seekHeldKey) {
        _seekRepeat = 0;
        _seekHeldKey = null;
      }
      return KeyEventResult.ignored;
    }
    // KeyRepeatEvent enables held-arrow continuous seek/volume; confirm
    // keys intentionally only react to the initial KeyDownEvent.
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final confirm = (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter) &&
        event is KeyDownEvent;
    if (!fullscreen) {
      if (confirm) {
        unawaited(_enterFullscreen());
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    // Yield to traversal only while an overlay button actually holds
    // primary focus — buttons are descendants of the surface node, so
    // hasFocus alone can't tell the two modes apart.
    if (_controlsVisible && !_surfaceFocus.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    if (confirm) {
      // Overlay up + surface focused: OK enters "button mode" rather than
      // toggling playback — the user surfaced the controls to reach them.
      if (_controlsVisible) {
        _playFocus.requestFocus();
      } else if (ready) {
        unawaited(_togglePlayback());
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final delta = key == LogicalKeyboardKey.arrowLeft ? -1 : 1;
      if (widget.live) {
        if (ready && !selecting) _switchChannel(delta);
      } else if (ready && durationMs > 0) {
        final step = _seekStepFor(event, key);
        unawaited(_seek(
            (positionMs + delta * step).clamp(0, durationMs).toInt()));
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown) {
      unawaited(MediaController.adjustVolume(
          key == LogicalKeyboardKey.arrowUp ? 1 : -1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _tapVideoToggle() {
    if (_controlsVisible) {
      _hideControls();
    } else {
      _showControls();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.entry.lines;
    final content = <Widget>[
      AspectRatio(
        aspectRatio: 16 / 9,
        child: _fullscreen
            ? const ColoredBox(color: Colors.black)
            : _videoSurface(fullscreen: false),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child:
              LocalizedText(error!, style: const TextStyle(color: Colors.red)),
        ),
      if (line != null) ...[
        const SizedBox(height: 12),
        _EpisodeStrip(
            episodes: lines[line] ?? const [],
            selectedUrl: episode?.url,
            enabled: ready && !selecting,
            onSelected: (next) => _select(next),
            onShowAll: _showAllEpisodes),
      ],
      Wrap(children: [
        if (widget.onOpenOriginal != null)
          TextButton.icon(
            onPressed:
                ready && !selecting ? () => unawaited(_openOriginal()) : null,
            icon: const Icon(Icons.open_in_new),
            label: const LocalizedText('返回原资源'),
          ),
        if (!widget.live)
          Tooltip(
              message: uiText(context, '下载剧集'),
              child: TextButton.icon(
                onPressed: episode == null ? null : _download,
                icon: const Icon(Icons.download_outlined),
                label: const LocalizedText('下载剧集'),
              )),
        if (episode != null &&
            widget.library.downloadedFile(widget.entry.id, episode!) != null)
          TextButton.icon(
            onPressed: ready ? () => _select(episode, local: true) : null,
            icon: const Icon(Icons.offline_pin_outlined),
            label: const LocalizedText('播放已下载文件'),
          ),
      ]),
      if (!widget.embedded) const Divider(),
      if (!widget.embedded)
        Text(widget.entry.description.isEmpty
            ? '暂无简介'
            : widget.entry.description),
    ];
    if (widget.embedded) return Column(children: content);
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.title, maxLines: 1)),
      body: ListView(padding: const EdgeInsets.all(16), children: content),
    );
  }
}

double _episodeTileHeight(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) * 2.4 + 16)
        .clamp(56.0, double.infinity);

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile(
      {super.key, required this.episode, required this.selected, this.onTap});

  final Episode episode;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
        selected: selected,
        button: true,
        enabled: onTap != null,
        child: Material(
            color: selected
                ? colors.primary.withValues(alpha: dark ? 0.18 : 0.08)
                : dark
                    ? colors.surfaceContainerHigh
                    : const Color(0xfff6f6f6),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onTap,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                        child: Text(episode.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? colors.primary
                                    : colors.onSurface)))))));
  }
}

class _EpisodeStrip extends StatefulWidget {
  const _EpisodeStrip(
      {required this.episodes,
      required this.selectedUrl,
      required this.enabled,
      required this.onSelected,
      required this.onShowAll});

  final List<Episode> episodes;
  final String? selectedUrl;
  final bool enabled;
  final ValueChanged<Episode> onSelected;
  final VoidCallback onShowAll;

  @override
  State<_EpisodeStrip> createState() => _EpisodeStripState();
}

class _EpisodeStripState extends State<_EpisodeStrip> {
  static const _cardWidth = 96.0;
  static const _spacing = 8.0;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _revealCurrent();
  }

  @override
  void didUpdateWidget(covariant _EpisodeStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedUrl != widget.selectedUrl ||
        !listEquals(oldWidget.episodes, widget.episodes)) {
      _revealCurrent();
    }
  }

  void _revealCurrent() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final index = widget.episodes
            .indexWhere((episode) => episode.url == widget.selectedUrl);
        if (index < 0) return;
        final offset = (index * (_cardWidth + _spacing) -
                (_scroll.position.viewportDimension - _cardWidth) / 2)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(offset);
      });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 3,
                    height: 16,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                const Flexible(
                    child: LocalizedText('选集',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600))),
              ]),
              Tooltip(
                  message: uiText(context, '全部剧集'),
                  child: TextButton(
                      onPressed:
                          widget.episodes.isEmpty ? null : widget.onShowAll,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                            child: LocalizedText(
                                '全部 ${widget.episodes.length} 集',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12))),
                        const Icon(Icons.chevron_right, size: 18),
                      ]))),
            ]),
        SizedBox(
            height: _episodeTileHeight(context),
            child: ListView.separated(
                key: const ValueKey('episode-strip'),
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemCount: widget.episodes.length,
                separatorBuilder: (_, index) => const SizedBox(width: _spacing),
                itemBuilder: (_, index) {
                  final item = widget.episodes[index];
                  return SizedBox(
                      width: _cardWidth,
                      child: _EpisodeTile(
                          key: ValueKey('episode-strip-$index'),
                          episode: item,
                          selected: item.url == widget.selectedUrl,
                          onTap: widget.enabled
                              ? () => widget.onSelected(item)
                              : null));
                })),
      ]);
}

class _EpisodeSheet extends StatefulWidget {
  const _EpisodeSheet(
      {required this.episodes,
      required this.selectedUrl,
      required this.enabled,
      required this.onSelected});

  final List<Episode> episodes;
  final String? selectedUrl;
  final bool enabled;
  final ValueChanged<Episode> onSelected;

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  final ScrollController _scroll = ScrollController();
  bool _descending = false;
  double _tileHeight = 56;

  @override
  void initState() {
    super.initState();
    _revealCurrent();
  }

  @override
  void didUpdateWidget(covariant _EpisodeSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedUrl != widget.selectedUrl) _revealCurrent();
  }

  void _revealCurrent() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        var index = widget.episodes
            .indexWhere((episode) => episode.url == widget.selectedUrl);
        if (index < 0) return;
        if (_descending) index = widget.episodes.length - 1 - index;
        final offset = ((index ~/ 2) * (_tileHeight + 8) -
                (_scroll.position.viewportDimension - _tileHeight) / 2)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(offset);
      });

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _tileHeight = _episodeTileHeight(context);
    return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(children: [
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        LocalizedText('全部剧集',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Tooltip(
                            message:
                                uiText(context, _descending ? '切换正序' : '切换倒序'),
                            child: TextButton.icon(
                                onPressed: () {
                                  setState(() => _descending = !_descending);
                                  if (_scroll.hasClients) _scroll.jumpTo(0);
                                },
                                icon: Icon(
                                    _descending
                                        ? Icons.arrow_upward
                                        : Icons.arrow_downward,
                                    size: 16),
                                label:
                                    LocalizedText(_descending ? '倒序' : '正序'))),
                        IconButton(
                            tooltip: uiText(context, '关闭全部剧集'),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, size: 22)),
                      ]),
                  const SizedBox(height: 8),
                  Expanded(
                      child: GridView.builder(
                          key: const ValueKey('episode-grid'),
                          controller: _scroll,
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisExtent: _tileHeight,
                                  mainAxisSpacing: 8,
                                  crossAxisSpacing: 8),
                          itemCount: widget.episodes.length,
                          itemBuilder: (_, index) {
                            final item = widget.episodes[_descending
                                ? widget.episodes.length - 1 - index
                                : index];
                            return _EpisodeTile(
                                key: ValueKey('episode-grid-$index'),
                                episode: item,
                                selected: item.url == widget.selectedUrl,
                                onTap: widget.enabled
                                    ? () => widget.onSelected(item)
                                    : null);
                          })),
                ]))));
  }
}

class _FullscreenPlayer extends StatelessWidget {
  const _FullscreenPlayer({required this.player});

  final _PlayerPageState player;

  // Back semantics on remotes: overlay hidden → wake it (focus moves to a
  // button); an overlay button focused → return focus to the video; video
  // focused → exit fullscreen entirely.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      // Focus changes drive canPop too, not just control visibility.
      animation: Listenable.merge(
          [player._repaintFullscreen, player._surfaceFocus]),
      builder: (context, _) => PopScope(
          canPop:
              player._controlsVisible && player._surfaceFocus.hasPrimaryFocus,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (player._controlsVisible) {
              player._surfaceFocus.requestFocus();
            } else {
              player._wakeControls();
            }
          },
          child: Scaffold(
              backgroundColor: Colors.black,
              body: Center(
                  child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: player._videoSurface(fullscreen: true))))));
}

/// Focusable wrapper for the video surface: draws a visible orange ring
/// while focused so remote users can tell where the D-pad focus is.
class _SurfaceFocus extends StatelessWidget {
  const _SurfaceFocus(
      {required this.node,
      required this.onKey,
      required this.child,
      this.autofocus = false});

  final FocusNode node;
  final KeyEventResult Function(KeyEvent event) onKey;
  final Widget child;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Focus(
      focusNode: node,
      autofocus: autofocus,
      onKeyEvent: (_, event) => onKey(event),
      child: AnimatedBuilder(
          animation: node,
          builder: (context, child) => DecoratedBox(
              decoration: BoxDecoration(
                  border: Border.all(
                      color: node.hasPrimaryFocus
                          ? const Color(0xFFFF7A00)
                          : Colors.transparent,
                      width: 2.5)),
              child: child),
          child: child));
}

/// DLNA device picker: runs SSDP discovery on open and lists renderers.
class _CastSheet extends StatefulWidget {
  const _CastSheet({required this.onPicked});
  final ValueChanged<CastDevice> onPicked;

  @override
  State<_CastSheet> createState() => _CastSheetState();
}

class _CastSheetState extends State<_CastSheet> {
  List<CastDevice> devices = const [];
  bool searching = true;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_scan());
  }

  Future<void> _scan() async {
    try {
      final found = await CastClient.discover();
      if (mounted) {
        setState(() {
          devices = found;
          searching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          searching = false;
          failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
                alignment: Alignment.centerLeft,
                child: LocalizedText('选择投屏设备',
                    style: TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(height: 12),
            if (searching)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator())
            else if (devices.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LocalizedText(
                      '未发现设备，请确认电视与手机在同一网络后重试'))
            else
              for (final device in devices)
                ListTile(
                    dense: true,
                    leading: const Icon(Icons.tv_outlined),
                    title: Text(device.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onPicked(device)),
            if (!searching)
              Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () {
                        setState(() {
                          devices = const [];
                          searching = true;
                          failed = false;
                        });
                        unawaited(_scan());
                      },
                      child: const LocalizedText('重新搜索'))),
          ])));
}
