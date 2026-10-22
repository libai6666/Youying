import 'package:flutter/material.dart';

import 'catalog.dart';
import 'ui_locale.dart';
import 'library.dart';
import 'main.dart' show DetailPage;
import 'offline_downloads.dart';
import 'player.dart';

class DownloadEpisodeSheet extends StatefulWidget {
  const DownloadEpisodeSheet(
      {super.key,
      required this.entry,
      required this.episodes,
      required this.library,
      this.current,
      this.headers = const {},
      this.resolveDownloadUrl});
  final MediaEntry entry;
  final List<Episode> episodes;
  final Library library;
  final Episode? current;
  final Map<String, String> headers;
  final Future<String?> Function(Episode episode)? resolveDownloadUrl;
  @override
  State<DownloadEpisodeSheet> createState() => _DownloadEpisodeSheetState();
}

class _DownloadEpisodeSheetState extends State<DownloadEpisodeSheet> {
  final Set<String> selected = {};
  bool reversed = false;
  bool submitting = false;
  String? message;

  @override
  void initState() {
    super.initState();
    final current = widget.current;
    if (current != null &&
        widget.library.offline.find(widget.entry.id, current) == null &&
        widget.library.downloadedFile(widget.entry.id, current) == null) {
      selected.add(current.url);
    }
  }

  List<Episode> get eligible => widget.episodes
      .where((episode) =>
          widget.library.offline.find(widget.entry.id, episode) == null &&
          widget.library.downloadedFile(widget.entry.id, episode) == null)
      .toList();

  Future<void> _enqueue() async {
    if (submitting) return;
    final episodes = eligible;
    final targets = selected.isEmpty
        ? episodes
        : episodes.where((episode) => selected.contains(episode.url)).toList();
    if (targets.isEmpty) {
      setState(() => message = '这些剧集已有任务，请在下载列表中继续或重试');
      return;
    }
    setState(() {
      submitting = true;
      message = null;
    });
    try {
      final downloadUrls = <String, String>{};
      final resolver = widget.resolveDownloadUrl;
      if (resolver != null) {
        for (final target in targets) {
          final resolved = await resolver(target);
          if (resolved != null) downloadUrls[target.url] = resolved;
        }
      }
      await widget.library.offline.enqueue(widget.entry, targets,
          headers: widget.headers, downloadUrls: downloadUrls);
      if (mounted) {
        setState(() {
          selected.clear();
          message = '已加入 ${targets.length} 集，请在下载列表查看进度';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => message =
            error is FormatException ? error.message : '加入下载任务失败，请重试');
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.library,
      builder: (context, _) {
        final episodes =
            reversed ? widget.episodes.reversed.toList() : widget.episodes;
        final pending = eligible;
        final count =
            pending.where((episode) => selected.contains(episode.url)).length;
        return SizedBox(
            height: MediaQuery.sizeOf(context).height * .84,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Expanded(
                              child: LocalizedText('下载剧集',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold))),
                          IconButton(
                              tooltip: uiText(context, '关闭下载选集'),
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close)),
                        ]),
                        Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              TextButton(
                                  onPressed: submitting
                                      ? null
                                      : () => setState(() {
                                            if (count == pending.length) {
                                              selected.clear();
                                            } else {
                                              selected.addAll(
                                                  pending.map((e) => e.url));
                                            }
                                          }),
                                  child: LocalizedText(
                                      count == pending.length && count > 0
                                          ? '取消全选'
                                          : '全选')),
                              IconButton(
                                  tooltip: uiText(context, '下载剧集排序'),
                                  onPressed: () =>
                                      setState(() => reversed = !reversed),
                                  icon: const Icon(Icons.sort)),
                            ]),
                      ])),
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: LocalizedText(
                          '${widget.entry.title} · 共 ${widget.episodes.length} 集 · 仅下载你有权保存的内容',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis))),
              Expanded(
                  child: GridView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 40 +
                              MediaQuery.textScalerOf(context).scale(14) * 2.4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8),
                      itemCount: episodes.length,
                      itemBuilder: (context, index) {
                        final episode = episodes[index];
                        final task = widget.library.offline
                            .find(widget.entry.id, episode);
                        final exists = task != null ||
                            widget.library
                                    .downloadedFile(widget.entry.id, episode) !=
                                null;
                        final checked =
                            !exists && selected.contains(episode.url);
                        return OutlinedButton(
                            key: ValueKey('download-episode-${episode.url}'),
                            style: OutlinedButton.styleFrom(
                                backgroundColor: checked
                                    ? const Color(0xfffff0e6)
                                    : const Color(0xfff7f7f7),
                                foregroundColor: checked
                                    ? const Color(0xffff681f)
                                    : const Color(0xff555555),
                                side: BorderSide(
                                    color: checked
                                        ? const Color(0xffff681f)
                                        : Colors.transparent),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8)),
                            onPressed: exists || submitting
                                ? null
                                : () => setState(() {
                                      if (!selected.add(episode.url)) {
                                        selected.remove(episode.url);
                                      }
                                    }),
                            child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(episode.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  if (exists)
                                    LocalizedText(task?.status ?? '已完成',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11)),
                                  if (checked)
                                    const Icon(Icons.check_circle, size: 16),
                                ]));
                      })),
              if (message != null)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: LocalizedText(message!)),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        Expanded(
                            child: FilledButton(
                                onPressed: submitting ? null : _enqueue,
                                child: LocalizedText(submitting
                                    ? '加入中…'
                                    : count == 0 || count == pending.length
                                        ? '全部开始'
                                        : '下载 $count 集'))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: OutlinedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const LocalizedText('查看下载列表'))),
                      ]))),
            ]));
      });
}

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, required this.library});
  final Library library;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const LocalizedText('我的下载')),
      body: DownloadsView(library: library));
}

class DownloadsView extends StatefulWidget {
  const DownloadsView(
      {super.key, required this.library, this.groupId, this.initialFilter = 0});
  final Library library;
  final String? groupId;
  final int initialFilter;
  @override
  State<DownloadsView> createState() => _DownloadsViewState();
}

class _DownloadsViewState extends State<DownloadsView> {
  late int filter;
  final Set<String> busy = {};
  bool _bulkBusy = false;
  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
    widget.library.offline.initialize();
  }

  Future<void> _action(DownloadTask task, String action) async {
    if (action == 'remove') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const LocalizedText('删除下载？'),
                  content: LocalizedText(
                      '${task.entry.title} · ${task.episode.name}\n同时移除已缓存的离线内容。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const LocalizedText('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const LocalizedText('删除'))
                  ]));
      if (confirmed != true || !mounted) return;
    }
    setState(() => busy.add(task.id));
    try {
      await widget.library.offline.action(action, task);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: LocalizedText('下载任务操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => busy.remove(task.id));
    }
  }

  Future<void> _bulk(String action) async {
    if (_bulkBusy) return;
    setState(() => _bulkBusy = true);
    try {
      final offline = widget.library.offline;
      if (widget.groupId == null) {
        if (action == 'pause') {
          await offline.pauseAll();
        } else {
          await offline.resumeAll();
        }
      } else {
        final group = groupDownloads(offline.tasks)
            .where((item) => item.id == widget.groupId)
            .firstOrNull;
        for (final task in group?.tasks ?? const <DownloadTask>[]) {
          if (action == 'pause' && task.active) {
            await offline.action('pause', task);
          } else if (action == 'resume' && task.state == 'paused') {
            await offline.action('resume', task);
          } else if (action == 'remove') {
            await offline.action('remove', task);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: LocalizedText('下载任务操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  Future<void> _removeAll(List<DownloadTask> scoped) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const LocalizedText('删除全部下载？'),
                content: LocalizedText(
                    '共 ${scoped.length} 项任务\n同时移除已缓存的离线内容。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const LocalizedText('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const LocalizedText('删除'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _bulkBusy = true);
    try {
      for (final task in scoped) {
        await widget.library.offline.action('remove', task);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: LocalizedText('下载任务操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  void _play(DownloadTask task) {
    final entry = MediaEntry.fromJson({
      ...task.entry.toJson(),
      'lines': {
        for (final line in task.entry.lines.entries)
          line.key: [
            for (final episode in line.value)
              if (widget.library.downloadedFile(task.entry.id, episode) != null)
                {'name': episode.name, 'url': episode.url}
          ],
      }
    });
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
            entry: entry,
            originalEntry: task.entry,
            onOpenOriginal: () =>
                _openOriginalResource(context, widget.library, task.entry),
            library: widget.library,
            initial: task.episode,
            preferOffline: true)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.library,
      builder: (context, _) {
        bool matches(DownloadTask task) =>
            filter == 0 || (filter == 1 ? !task.completed : task.completed);
        final groups = groupDownloads(widget.library.offline.tasks)
            .where(
                (group) => widget.groupId == null || group.id == widget.groupId)
            .toList();
        final visibleGroups =
            groups.where((group) => group.tasks.any(matches)).toList();
        final tasks =
            groups.expand((group) => group.tasks).where(matches).toList();
        final showLegacy = widget.groupId == null &&
            filter != 1 &&
            widget.library.downloads.isNotEmpty;
        final scopedTasks = widget.groupId == null
            ? widget.library.offline.tasks
            : groups.expand((group) => group.tasks).toList();
        final activeCount =
            scopedTasks.where((task) => task.active).length;
        final pausedCount =
            scopedTasks.where((task) => task.state == 'paused').length;
        return Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (index, title) in [
                      (0, '全部'),
                      (1, '正在下载'),
                      (2, '已完成')
                    ])
                      ChoiceChip(
                          label: LocalizedText(title),
                          selected: filter == index,
                          onSelected: (_) => setState(() => filter = index)),
                    if (activeCount > 0)
                      TextButton.icon(
                          onPressed: _bulkBusy ? null : () => _bulk('pause'),
                          icon: const Icon(Icons.pause, size: 18),
                          label: const LocalizedText('全部暂停')),
                    if (pausedCount > 0)
                      TextButton.icon(
                          onPressed: _bulkBusy ? null : () => _bulk('resume'),
                          icon: const Icon(Icons.play_arrow, size: 18),
                          label: const LocalizedText('全部继续')),
                    if (scopedTasks.isNotEmpty)
                      TextButton.icon(
                          onPressed: _bulkBusy
                              ? null
                              : () => _removeAll(scopedTasks),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const LocalizedText('全部删除')),
                  ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LocalizedText(
                  widget.groupId == null
                      ? '同时下载最多 ${widget.library.offline.parallelism} 集 · 可在设置中调整'
                      : groups.isEmpty
                          ? '该影片已无下载任务'
                          : groups.first.entry.source,
                  style: Theme.of(context).textTheme.bodySmall)),
          if (!widget.library.offline.available)
            const Padding(
                padding: EdgeInsets.all(12),
                child: LocalizedText('离线服务尚不可用，请重新启动包含原生更新的调试包')),
          Expanded(
              child: ListView(padding: const EdgeInsets.all(12), children: [
            if (tasks.isEmpty && !showLegacy)
              const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: LocalizedText('暂无下载任务'))),
            if (widget.groupId == null)
              for (final group in visibleGroups)
                _DownloadGroupTile(
                    group: group,
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                            builder: (_) => DownloadsGroupPage(
                                library: widget.library,
                                group: group,
                                initialFilter: filter))))
            else
              for (final task in tasks)
                _DownloadTaskTile(
                    task: task,
                    progress: widget.library
                        .watchProgress(task.entry.id, task.episode),
                    busy: busy.contains(task.id),
                    onPlay: () => _play(task),
                    onAction: (action) => _action(task, action)),
            if (showLegacy) ...[
              const LocalizedText('旧版已下载文件（在对应影片中选择“播放已下载文件”）'),
              for (final _ in widget.library.downloads.entries)
                const ListTile(
                    leading: Icon(Icons.offline_pin),
                    title: LocalizedText('已保存的本地视频')),
            ],
          ])),
        ]);
      });
}

class DownloadsGroupPage extends StatelessWidget {
  const DownloadsGroupPage(
      {super.key,
      required this.library,
      required this.group,
      this.initialFilter = 0});
  final Library library;
  final DownloadGroup group;
  final int initialFilter;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(group.entry.title,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton.icon(
                onPressed: () =>
                    _openOriginalResource(context, library, group.entry),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const LocalizedText('原资源')),
          ]),
      body: DownloadsView(
          library: library, groupId: group.id, initialFilter: initialFilter));
}

Future<void> _openOriginalResource(
        BuildContext context, Library library, MediaEntry entry) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DetailPage(entry: entry, library: library)));

class _DownloadPoster extends StatelessWidget {
  const _DownloadPoster(
      {required this.entry, required this.width, required this.height});
  final MediaEntry entry;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: entry.poster.isEmpty
                  ? const Icon(Icons.movie_outlined)
                  : Image.network(entry.poster,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) =>
                          const Icon(Icons.movie_outlined)))));
}

class _DownloadGroupTile extends StatelessWidget {
  const _DownloadGroupTile({required this.group, required this.onTap});
  final DownloadGroup group;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final statuses = <String, int>{};
    for (final task in group.tasks.where((task) => !task.completed)) {
      statuses.update(task.status, (count) => count + 1, ifAbsent: () => 1);
    }
    return Column(key: ValueKey('download-group-${group.id}'), children: [
      InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                _DownloadPoster(entry: group.entry, width: 96, height: 68),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(group.entry.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(group.entry.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                      LocalizedText(
                          '已缓存 ${group.completedCount} 集 · ${_bytes(group.bytes)}',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (statuses.isNotEmpty)
                        LocalizedText(
                            statuses.entries
                                .map((entry) =>
                                    '${uiText(context, entry.key)} ${entry.value} ${uiText(context, '集')}')
                                .join(' · '),
                            style: Theme.of(context).textTheme.bodySmall),
                    ])),
                const Icon(Icons.chevron_right),
              ]))),
      const Divider(height: 1),
    ]);
  }
}

class _DownloadTaskTile extends StatelessWidget {
  const _DownloadTaskTile(
      {required this.task,
      required this.progress,
      required this.busy,
      required this.onPlay,
      required this.onAction});
  final DownloadTask task;
  final WatchProgress progress;
  final bool busy;
  final VoidCallback onPlay;
  final ValueChanged<String> onAction;
  @override
  Widget build(BuildContext context) =>
      Column(key: ValueKey('download-task-${task.id}'), children: [
        InkWell(
            onTap: task.completed && !busy ? onPlay : null,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  _DownloadPoster(entry: task.entry, width: 76, height: 54),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        LocalizedText(
                            '${task.entry.title} ${task.episode.name}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        LocalizedText(
                            '${task.status} · ${_bytes(task.bytes)}${task.total > 0 && !task.completed ? ' / ${_bytes(task.total)}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 4),
                        LocalizedText('观看进度：${progress.label}',
                            key: ValueKey('watch-progress-${task.id}'),
                            style: Theme.of(context).textTheme.bodySmall),
                        if (!task.completed) ...[
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                              value: task.percent < 0
                                  ? null
                                  : (task.percent / 100).clamp(0.0, 1.0)),
                        ],
                        if (task.state == 'failed')
                          LocalizedText(task.failureMessage,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.error)),
                      ])),
                  PopupMenuButton<String>(
                      tooltip: uiText(context, '管理${task.episode.name}'),
                      enabled: !busy && task.state != 'removing',
                      onSelected: (action) {
                        if (action == 'play') {
                          onPlay();
                        } else {
                          onAction(action);
                        }
                      },
                      itemBuilder: (_) => [
                            if (task.completed)
                              const PopupMenuItem(
                                  value: 'play', child: LocalizedText('离线播放')),
                            if (task.active)
                              const PopupMenuItem(
                                  value: 'pause', child: LocalizedText('暂停')),
                            if (task.state == 'paused')
                              const PopupMenuItem(
                                  value: 'resume', child: LocalizedText('继续')),
                            if (task.state == 'failed')
                              const PopupMenuItem(
                                  value: 'retry', child: LocalizedText('重试')),
                            const PopupMenuItem(
                                value: 'remove', child: LocalizedText('删除')),
                          ]),
                ]))),
        const Divider(height: 1),
      ]);
}

String _bytes(int value) => value < 1024 * 1024
    ? '${(value / 1024).toStringAsFixed(1)} KB'
    : '${(value / 1048576).toStringAsFixed(1)} MB';
