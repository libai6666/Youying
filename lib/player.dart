import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';
import 'library.dart';

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
      {int startMs = 0, Map<String, String> headers = const {}}) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty) {
      throw const FormatException('只播放 HTTPS 媒体或已下载文件');
    }
    await call('open',
        {'url': url, 'startMs': startMs, 'headers': headers, 'play': true});
  }

  Future<void> openFile(String path, {int startMs = 0}) =>
      call('open', {'filePath': path, 'startMs': startMs, 'play': true});
  Future<void> pause() => call('pause');
  Future<void> play() => call('play');
  Future<void> seek(int ms) => call('seek', {'positionMs': ms});
  Future<void> setRate(double rate) => call('setRate', {'rate': rate});
  Future<void> dispose() => call('dispose');

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
      this.embedded = false,
      this.onPlaybackChanged,
      this.headers = const {}});
  final MediaEntry entry;
  final Library library;
  final Episode? initial;
  final int? initialPositionMs;
  final bool embedded;
  final void Function(Episode episode, int positionMs)? onPlaybackChanged;
  final Map<String, String> headers;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final MediaController controller = MediaController();
  StreamSubscription<Map<dynamic, dynamic>>? subscription;
  String? line;
  Episode? episode;
  bool ready = false;
  bool playing = false;
  bool loading = false;
  bool downloading = false;
  bool selecting = false;
  int downloadedBytes = 0;
  int? downloadTotal;
  String? error;
  int positionMs = 0;
  int durationMs = 0;
  double rate = 1;

  @override
  void initState() {
    super.initState();
    for (final group in widget.entry.lines.entries) {
      if (group.value.isNotEmpty) {
        line ??= group.key;
        episode ??= group.value.first;
        if (widget.initial != null &&
            group.value.any((item) => item.url == widget.initial!.url)) {
          line = group.key;
          episode = widget.initial;
          break;
        }
      }
    }
    _initialize();
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
    setState(() {
      switch (event['type']) {
        case 'playing':
          playing = event['value'] == true;
        case 'buffering':
          loading = event['value'] == true;
        case 'position':
          final value = event['value'];
          if (value is num) positionMs = value.toInt();
        case 'duration':
          final value = event['value'];
          if (value is num) durationMs = value.toInt();
        case 'error':
          error = '播放失败，请检查地址、格式和网络';
      }
    });
    if (episode != null) widget.onPlaybackChanged?.call(episode!, positionMs);
  }

  Future<void> _select(Episode? next,
      {bool local = false, int? startMs}) async {
    if (next == null || !ready || selecting) return;
    setState(() => selecting = true);
    try {
      await _openEpisode(next, local: local, startMs: startMs);
    } finally {
      if (mounted) setState(() => selecting = false);
    }
  }

  Future<void> _openEpisode(Episode next,
      {bool local = false, int? startMs}) async {
    if (episode != null && positionMs > 0 && episode!.url != next.url) {
      await widget.library
          .recordPlay(widget.entry, episode: episode, position: positionMs);
    }
    if (!mounted) return;
    setState(() {
      episode = next;
      error = null;
      positionMs = 0;
      durationMs = 0;
    });
    widget.onPlaybackChanged?.call(next, startMs ?? 0);
    try {
      if (local) {
        final path = widget.library.downloadedFile(widget.entry.id, next);
        if (path == null) throw const FormatException('没有该集的已下载文件');
        await controller.openFile(path,
            startMs: startMs ??
                widget.library.resumePosition(widget.entry.id, next));
      } else {
        await controller.open(next.url,
            startMs:
                startMs ?? widget.library.resumePosition(widget.entry.id, next),
            headers: widget.headers);
      }
      await widget.library.recordPlay(widget.entry, episode: next);
    } catch (_) {
      if (mounted) setState(() => error = '播放地址不可用');
    }
  }

  Future<void> _download() async {
    if (episode == null || downloading) return;
    final target = episode!;
    setState(() {
      downloading = true;
      downloadedBytes = 0;
      downloadTotal = null;
    });
    try {
      await widget.library.download(
        target,
        widget.entry.id,
        headers: widget.headers,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              downloadedBytes = received;
              downloadTotal = total;
            });
          }
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件已保存到本应用的私有目录')),
        );
      }
    } catch (failure) {
      if (mounted) {
        final message = failure is FormatException
            ? failure.message
            : '下载失败，请检查网络、源权限和存储空间';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    if (ready) {
      widget.library
          .recordPlay(widget.entry, episode: episode, position: positionMs);
      controller.dispose();
    }
    super.dispose();
  }

  String _time(int ms) {
    final seconds = (ms / 1000).floor().clamp(0, 359999);
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.entry.lines;
    final content = <Widget>[
      AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: ready
              ? controller.videoView()
              : Center(
                  child: error == null
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.play_circle_outline,
                          color: Colors.white54, size: 48)),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
      if (loading) const LinearProgressIndicator(),
      Slider(
        value: positionMs.clamp(0, durationMs > 0 ? durationMs : 1).toDouble(),
        max: (durationMs > 0 ? durationMs : 1).toDouble(),
        onChanged: durationMs == 0 || !ready
            ? null
            : (value) => setState(() => positionMs = value.toInt()),
        onChangeEnd: durationMs == 0 || !ready
            ? null
            : (value) => controller.seek(value.toInt()),
      ),
      Row(children: [
        IconButton(
          tooltip: playing ? '暂停' : '播放',
          onPressed: !ready
              ? null
              : () => playing ? controller.pause() : controller.play(),
          icon: Icon(playing ? Icons.pause : Icons.play_arrow),
        ),
        Expanded(
            child: Text('${_time(positionMs)} / ${_time(durationMs)}',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12))),
        PopupMenuButton<double>(
          tooltip: '倍速',
          initialValue: rate,
          onSelected: ready
              ? (value) {
                  setState(() => rate = value);
                  controller.setRate(value);
                }
              : null,
          itemBuilder: (_) => [1.0, 1.25, 1.5, 2.0]
              .map((value) =>
                  PopupMenuItem(value: value, child: Text('${value}x')))
              .toList(),
          child: Padding(
              padding: const EdgeInsets.all(8), child: Text('${rate}x')),
        ),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 8, children: [
        for (final item in lines.keys)
          ChoiceChip(
              label: Text(item),
              selected: line == item,
              onSelected: selecting
                  ? null
                  : (_) {
                      final target = Episode.onLine(
                          lines[item] ?? [], episode, lines[line] ?? []);
                      if (target == null || line == item) return;
                      final matches =
                          target.name.trim() == episode?.name.trim() ||
                              (Episode.ordinal(target.name) != null &&
                                  Episode.ordinal(target.name) ==
                                      Episode.ordinal(episode?.name ?? ''));
                      final position = matches ? positionMs : 0;
                      setState(() {
                        line = item;
                        if (!ready) episode = target;
                      });
                      if (ready) _select(target, startMs: position);
                    }),
      ]),
      if (line != null) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final item in lines[line] ?? const <Episode>[])
            OutlinedButton(
              onPressed: ready && !selecting ? () => _select(item) : null,
              child: Text(item.name),
            ),
        ]),
      ],
      Wrap(children: [
        TextButton.icon(
          onPressed: downloading || episode == null ? null : _download,
          icon: const Icon(Icons.download_outlined),
          label: Text(downloading
              ? '下载 ${(downloadedBytes / 1048576).toStringAsFixed(1)} MB'
              : '下载本集'),
        ),
        if (episode != null &&
            widget.library.downloadedFile(widget.entry.id, episode!) != null)
          TextButton.icon(
            onPressed: ready ? () => _select(episode, local: true) : null,
            icon: const Icon(Icons.offline_pin_outlined),
            label: const Text('播放已下载文件'),
          ),
      ]),
      if (downloading)
        LinearProgressIndicator(
            value: downloadTotal == null || downloadTotal == 0
                ? null
                : (downloadedBytes / downloadTotal!).clamp(0.0, 1.0)),
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
