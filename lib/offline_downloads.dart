import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'catalog.dart';

class DownloadTask {
  const DownloadTask(
      {required this.id,
      required this.entry,
      required this.episode,
      required this.state,
      this.bytes = 0,
      this.total = -1,
      this.percent = -1,
      this.waitingForNetwork = false,
      this.error = ''});
  final String id;
  final MediaEntry entry;
  final Episode episode;
  final String state;
  final int bytes;
  final int total;
  final double percent;
  final bool waitingForNetwork;
  final String error;
  bool get completed => state == 'completed';
  bool get active => state == 'queued' || state == 'downloading';

  factory DownloadTask.fromJson(Map<dynamic, dynamic> value) => DownloadTask(
        id: value['id'] as String,
        entry: MediaEntry.fromJson(value['entry'] is String
            ? jsonDecode(value['entry'] as String)
            : value['entry']),
        episode: Episode(
            name: value['episodeName'] as String, url: value['url'] as String),
        state: value['state'] as String,
        bytes: (value['bytes'] as num?)?.toInt() ?? 0,
        total: (value['total'] as num?)?.toInt() ?? -1,
        percent: (value['percent'] as num?)?.toDouble() ?? -1,
        waitingForNetwork: value['waitingForNetwork'] == true,
        error: value['error'] as String? ?? '',
      );

  String get status => switch (state) {
        'completed' => '已完成',
        'downloading' => '下载中',
        'queued' => waitingForNetwork ? '等待网络' : '排队中',
        'paused' => '已暂停',
        'removing' => '删除中',
        'failed' => '下载失败',
        _ => '等待中',
      };

  String get failureMessage => switch (error) {
        'DRM_OFFLINE_LICENSE_REQUIRED' => '该线路需要平台提供 DRM 离线许可，当前无法下载',
        'HLS_ENCRYPTION_UNSUPPORTED' => '该线路使用不支持的采样加密；普通 AES-128 HLS 可下载',
        'LIVE_UNSUPPORTED' => '直播或未结束的 HLS 不支持离线下载',
        'HTTPS_REQUIRED' => '下载地址或分片必须使用 HTTPS',
        'MANIFEST_INVALID' => 'HLS 密钥声明格式无效，请更换线路',
        'MANIFEST_TOO_LARGE' => 'HLS 清单超过大小限制',
        _ => '请检查网络、来源下载授权或存储空间后重试',
      };
}

class DownloadGroup {
  DownloadGroup._(this.entry, this.tasks);
  final MediaEntry entry;
  final List<DownloadTask> tasks;
  String get id => jsonEncode([entry.source, entry.id]);
  int get completedCount => tasks.where((task) => task.completed).length;
  int get bytes =>
      tasks.fold(0, (sum, task) => sum + (task.bytes < 0 ? 0 : task.bytes));
}

List<DownloadGroup> groupDownloads(Iterable<DownloadTask> tasks) {
  final groups = <String, List<DownloadTask>>{};
  for (final task in tasks) {
    groups
        .putIfAbsent(jsonEncode([task.entry.source, task.entry.id]), () => [])
        .add(task);
  }
  return [
    for (final items in groups.values) _downloadGroup(items),
  ];
}

DownloadGroup _downloadGroup(List<DownloadTask> items) {
  final entry = items.first.entry;
  final episodes = entry.lines.values.expand((line) => line).toList();
  final order = <String, int>{
    for (var index = 0; index < episodes.length; index++)
      episodes[index].url: index,
  };
  int rank(DownloadTask task) =>
      order[task.episode.url] ??
      episodes.length +
          (Episode.ordinal(task.episode.name) ?? items.indexOf(task));
  final sorted = List<DownloadTask>.of(items)
    ..sort((a, b) => rank(a).compareTo(rank(b)));
  return DownloadGroup._(entry, List.unmodifiable(sorted));
}

class OfflineDownloads extends ChangeNotifier {
  OfflineDownloads(
      {this.methods = const MethodChannel('youying/downloads/methods'),
      this.events = const EventChannel('youying/downloads/events')});
  final MethodChannel methods;
  final EventChannel events;
  StreamSubscription<dynamic>? _subscription;
  Future<void>? _initializing;
  bool _disposed = false;
  bool available = false;
  int parallelism = 3;
  List<DownloadTask> tasks = const [];

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      final snapshot =
          await methods.invokeMapMethod<dynamic, dynamic>('initialize');
      if (_disposed) return;
      available = true;
      _snapshot(snapshot);
      _subscription = events.receiveBroadcastStream().listen(_snapshot,
          onError: (Object _) {
        if (!_disposed) {
          available = false;
          notifyListeners();
        }
      });
    } on MissingPluginException {
      available = false;
    } on PlatformException {
      available = false;
    }
    if (!_disposed) notifyListeners();
  }

  void _snapshot(dynamic data) {
    if (_disposed || data is! Map) return;
    parallelism = ((data['parallelism'] as num?)?.toInt() ?? 3).clamp(1, 10);
    final next = <DownloadTask>[];
    for (final value in data['tasks'] as List? ?? const []) {
      try {
        next.add(DownloadTask.fromJson(value as Map));
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    tasks = next;
    notifyListeners();
  }

  DownloadTask? find(String mediaId, Episode episode) {
    for (final task in tasks) {
      if (task.entry.id == mediaId && task.episode.url == episode.url) {
        return task;
      }
    }
    return null;
  }

  Future<void> enqueue(MediaEntry entry, Iterable<Episode> episodes,
      {Map<String, String> headers = const {},
      Map<String, String> downloadUrls = const {}}) async {
    await initialize();
    if (!available) throw const FormatException('离线下载服务不可用；原生功能更新后请重新安装调试包');
    parseHeaders(jsonEncode(headers));
    final mediaPath = RegExp(r'\.(m3u8|mp4|webm)$', caseSensitive: false);
    final unique = <String, Episode>{};
    for (final episode in episodes) {
      final uri = SourceEndpoint.parseHttps(episode.url);
      if (!mediaPath.hasMatch(uri.path)) {
        throw const FormatException('当前支持 MP4、WebM 与 HLS 点播下载');
      }
      final override = downloadUrls[episode.url];
      if (override != null &&
          !mediaPath.hasMatch(SourceEndpoint.parseHttps(override).path)) {
        throw const FormatException('下载地址格式无效');
      }
      if (find(entry.id, episode) == null) unique[episode.url] = episode;
    }
    if (unique.isEmpty) return;
    await methods.invokeMethod<void>('enqueue', {
      'items': [
        for (final episode in unique.values)
          {
            'entry': jsonEncode(entry.toJson()),
            'episodeName': episode.name,
            'url': episode.url,
            'downloadUrl': downloadUrls[episode.url],
            'headers': headers,
          }
      ]
    });
  }

  Future<void> action(String method, DownloadTask task) =>
      methods.invokeMethod<void>(method, {'id': task.id});

  Future<void> pauseAll() => methods.invokeMethod<void>('pauseAll');
  Future<void> resumeAll() => methods.invokeMethod<void>('resumeAll');

  Future<void> setParallelism(int value) async {
    if (value < 1 || value > 10) throw const FormatException('并发数必须为 1～10');
    await initialize();
    if (!available) throw const FormatException('离线下载服务不可用，请重新启动最新版调试包');
    final data = await methods
        .invokeMapMethod<dynamic, dynamic>('setParallelism', {'value': value});
    _snapshot(data);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
