part of 'main.dart';

const _orange = Color(0xffff6500);
const _ink = Color(0xff303030);
const _muted = Color(0xff999999);
const _canvas = Color(0xfff7f7f7);

ThemeData youyingTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: _orange, primary: _orange),
      scaffoldBackgroundColor: _canvas,
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
          backgroundColor: _canvas,
          surfaceTintColor: Colors.transparent,
          elevation: 0),
      textTheme: const TextTheme(
          bodyMedium: TextStyle(color: _ink),
          bodySmall: TextStyle(color: _muted)),
      dividerColor: const Color(0xffeeeeee),
    );

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.library, this.browseClient});
  final Library library;
  final CatalogClient? browseClient;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DirectoryController browse =
      DirectoryController(widget.library, client: widget.browseClient);
  int selected = 0;
  String category = '首页';
  String ranking = '电视剧';
  bool hideContinue = false;
  final Map<String, CatalogFilters> _catalogFilters = {};

  @override
  void initState() {
    super.initState();
    browse;
  }

  @override
  void dispose() {
    browse.dispose();
    super.dispose();
  }

  void _open(String title, Widget child) => Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              Scaffold(appBar: AppBar(title: Text(title)), body: child)));
  void _search() => _open('搜索', SearchPage(library: widget.library));
  void _settings() => _open('设置', SettingsPage(library: widget.library));
  void _history() => _open('观看历史', _SavedEntries(library: widget.library));
  void _downloads() =>
      _open('我的下载', LibraryPage(library: widget.library, showHistory: false));
  void _detail(MediaEntry entry) => Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => DetailPage(
              entry: entry,
              library: widget.library,
              variants: browse.variantsFor(entry))));

  void _selectCategory(String label) {
    setState(() {
      selected = 0;
      category = label;
    });
    browse.ensureLabel(label);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([widget.library, browse]),
        builder: (context, _) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: selected == 1
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          child: Scaffold(
            body: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: selected == 1
                    ? [const Color(0xff27212a), _canvas, _canvas]
                    : [const Color(0xffffd6af), _canvas, _canvas],
                stops: const [0, 0.33, 1],
              )),
              child: SafeArea(
                  bottom: false,
                  child: IndexedStack(index: selected, children: [
                    _home(),
                    _rankings(),
                    _profile(),
                  ])),
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: selected,
              onTap: (index) {
                setState(() => selected = index);
                if (index == 1) browse.ensureLabel(ranking);
              },
              backgroundColor: Colors.white,
              selectedItemColor: _orange,
              unselectedItemColor: const Color(0xffcccccc),
              selectedFontSize: 10,
              unselectedFontSize: 10,
              type: BottomNavigationBarType.fixed,
              elevation: 0,
              items: const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.home_filled), label: '首页'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.bar_chart), label: '排行榜'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.account_circle), label: '我的'),
              ],
            ),
          ),
        ),
      );

  Widget _sourcePicker({bool dark = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(children: [
          Expanded(
              child: Text('多源聚合 · ${widget.library.enabledSources.length} 个来源',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: dark ? Colors.white70 : _muted))),
          Text(selected == 1 ? '聚合更新顺序 · 非热度榜' : '更新推荐 · 非平台热度',
              style: TextStyle(
                  fontSize: 10, color: dark ? Colors.white70 : _muted)),
        ]),
      );

  Widget _home() => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 0),
            child: Row(children: [
              Expanded(
                  child: Material(
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  onTap: _search,
                  borderRadius: BorderRadius.circular(24),
                  child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(children: [
                        Icon(Icons.search, size: 20, color: Color(0xff777777)),
                        SizedBox(width: 8),
                        Text('请输入关键字',
                            style: TextStyle(fontSize: 13, color: _muted))
                      ])),
                ),
              )),
              IconButton(
                  tooltip: '我的下载',
                  onPressed: _downloads,
                  icon: const Icon(Icons.downloading_outlined, size: 24)),
              IconButton(
                  tooltip: '观看历史',
                  onPressed: _history,
                  icon: const Icon(Icons.history, size: 24)),
            ])),
        _tabs(browseTabs, category, _selectCategory),
        Expanded(
            child: Stack(children: [
          RefreshIndicator(
              onRefresh: browse.refresh,
              child: ListView(
                key: PageStorageKey('home-$category'),
                padding: const EdgeInsets.only(bottom: 65),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _sourcePicker(),
                  if (!browse.hasSources)
                    _emptySources()
                  else if (category == '首页')
                    ..._homeSections()
                  else
                    _categoryContent(category),
                ],
              )),
          if (!hideContinue && widget.library.history.isNotEmpty)
            Positioned(
                left: 12, right: 12, bottom: 6, child: _continueWatching()),
        ])),
      ]);

  List<Widget> _homeSections() {
    final entries = browse.feedFor('电视剧')?.entries ?? [];
    return [
      if (entries.isNotEmpty)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _Spotlight(
                key: ValueKey(entries.first.id),
                entries: entries.take(5).toList(),
                onTap: _detail)),
      if (browse.loadingCategories) const _FeedLoading(),
      if (browse.categoryError != null)
        _Feedback(
            message: browse.categoryError!,
            action: '重试分类',
            onTap: browse.refresh),
      for (final (title, label) in [
        ('热播剧推荐', '电视剧'),
        ('热播综艺', '综艺'),
        ('热播动漫', '动漫')
      ])
        if (browse.supports(label)) _posterSection(title, label),
      if (browse.sourceIssues.isNotEmpty)
        ExpansionTile(
            key: const PageStorageKey('home-source-issues'),
            title: const Text('部分内容来源暂时不可用',
                style: TextStyle(fontSize: 12, color: _muted)),
            children: [
              for (final issue in browse.sourceIssues.entries)
                ListTile(
                    dense: true,
                    title: Text(issue.key),
                    subtitle: Text(issue.value))
            ]),
    ];
  }

  Widget _posterSection(String title, String label) {
    final feed = browse.feedFor(label);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _SectionHeader(
          title: title,
          onTap: () => _selectCategory(label == '动漫' ? '二次元动漫' : label)),
      if (feed?.loading == true) const _FeedLoading(),
      if (feed?.error != null)
        _Feedback(
            message: feed!.error!,
            action: '重试',
            onTap: () => browse.loadLabel(label, retry: true)),
      if (feed?.loaded == true)
        if (feed!.entries.isEmpty)
          const _Feedback(message: '暂未取得内容，可在更多中继续加载')
        else
          _PosterStrip(entries: feed.entries.take(10).toList(), onTap: _detail),
    ]);
  }

  Widget _categoryContent(String label, {bool ranked = false}) {
    if (browse.loadingCategories) return const _FeedLoading();
    if (browse.categoryError != null) {
      return _Feedback(
          message: browse.categoryError!, action: '重试', onTap: browse.refresh);
    }
    if (!browse.supports(label)) {
      return _Feedback(
          message: label == '电视直播' ? '当前为点播源，未接入电视直播' : '已启用来源未提供“$label”分类');
    }
    final feed = browse.feedFor(label);
    if (feed == null) {
      return _Feedback(
          message: '点击加载该分类',
          action: '加载',
          onTap: () => browse.loadLabel(label));
    }
    final filters = _catalogFilters[label] ?? const CatalogFilters();
    final entries = ranked ? feed.entries : filters.apply(feed.groups);
    return Column(children: [
      if (!ranked && label != '电视直播')
        _filters(label, feed, filters, entries.length),
      if (ranked)
        for (final entry in entries)
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _CatalogCard(entry: entry, onTap: () => _detail(entry)))
      else
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: LayoutBuilder(builder: (context, constraints) {
              final columns = (constraints.maxWidth / 110).floor().clamp(3, 6);
              final width =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(spacing: 8, runSpacing: 14, children: [
                for (final entry in entries)
                  SizedBox(
                      width: width,
                      child: _PosterTile(
                          entry: entry, onTap: () => _detail(entry))),
              ]);
            })),
      if (feed.loading) const _FeedLoading(),
      if (feed.error != null)
        _Feedback(
            message: feed.error!,
            action: '重试',
            onTap: () =>
                browse.loadLabel(label, more: feed.loaded, retry: true)),
      if (!feed.loading && feed.error == null && entries.isEmpty)
        _Feedback(
            message: !ranked && feed.entries.isNotEmpty
                ? '当前已加载内容没有匹配项，可调整筛选或加载更多'
                : feed.hasMore
                    ? '暂未取得内容，可继续加载其他子分类'
                    : '该分类暂无内容'),
      if (feed.issues.isNotEmpty && feed.error == null)
        ExpansionTile(
            key: PageStorageKey(
                'source-issues-${ranked ? 'ranking' : 'home'}-$label'),
            title: const Text('部分来源加载失败', style: TextStyle(fontSize: 12)),
            children: [
              TextButton(
                  onPressed: () => browse.loadLabel(label, retry: true),
                  child: const Text('重试未完成来源'))
            ]),
      if (!feed.loading && feed.error == null && feed.hasMore)
        TextButton(
            onPressed: () => browse.loadLabel(label, more: true),
            child: const Text('加载更多')),
    ]);
  }

  Widget _filterRow(String label, String selected, List<String> values,
          ValueChanged<String> onChanged,
          {Set<String> disabled = const {}}) =>
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            SizedBox(
                width: 32,
                child: Text(label,
                    style: const TextStyle(fontSize: 11, color: _muted))),
            Expanded(
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final value in values)
                        Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: ChoiceChip(
                              key: ValueKey('filter-$category-$label-$value'),
                              label: Text(value.isEmpty ? '全部' : value),
                              selected: selected == value,
                              showCheckmark: false,
                              onSelected: disabled.contains(value)
                                  ? null
                                  : (_) => onChanged(value),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              backgroundColor: Colors.transparent,
                              selectedColor: _orange.withValues(alpha: 0.12),
                              labelStyle: TextStyle(
                                  fontSize: 11,
                                  color: disabled.contains(value)
                                      ? _muted
                                      : selected == value
                                          ? _orange
                                          : _ink),
                            )),
                    ]))),
          ]));

  Widget _filters(
      String label, DirectoryFeed feed, CatalogFilters filters, int count) {
    final all = feed.rawEntries;
    final hot = all.any((e) => (e.popularity ?? 0) > 0);
    final rated = all.any((e) => e.rating != null);
    void change(CatalogFilters next) =>
        setState(() => _catalogFilters[label] = next);
    List<String> options(Iterable<String> values) =>
        ['', ...values.where((v) => v.isNotEmpty).toSet()];
    final years = {
      for (var i = 0; i < 10; i++) '${DateTime.now().year - i}',
      filters.year,
      ...all.map((e) => catalogYear(e.year))
    }..remove('');
    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _filterRow(
              '排序',
              switch (filters.order) {
                CatalogOrder.latest => '最新',
                CatalogOrder.popular => '最热',
                CatalogOrder.rating => '好评'
              },
              ['最新', '最热', '好评'],
              (value) => change(filters.copyWith(
                      order: switch (value) {
                    '最热' => CatalogOrder.popular,
                    '好评' => CatalogOrder.rating,
                    _ => CatalogOrder.latest
                  })),
              disabled: {if (!hot) '最热', if (!rated) '好评'}),
          _filterRow(
              '类型',
              filters.genre,
              options([
                ...catalogGenreOptions(label),
                filters.genre,
                ...all.expand(catalogGenres).where((g) => ![
                      '电影',
                      '电视',
                      '电视剧',
                      '连续',
                      '连续剧',
                      '综艺',
                      '动漫',
                      '国产',
                      '国产剧',
                      '欧美',
                      '欧美剧',
                      '日',
                      '日本剧',
                      '韩',
                      '韩国剧',
                      '台湾',
                      '台湾剧',
                      '香港',
                      '香港剧',
                      '短',
                      '短剧'
                    ].contains(g))
              ]),
              (value) => change(filters.copyWith(genre: value))),
          _filterRow(
              '地区',
              filters.area,
              options([
                '大陆',
                '香港',
                '台湾',
                '美国',
                '法国',
                '英国',
                '日本',
                '韩国',
                '德国',
                '泰国',
                filters.area,
                ...all.expand((e) => catalogTokens(e.area, area: true))
              ]),
              (value) => change(filters.copyWith(area: value))),
          _filterRow(
              '语言',
              filters.language,
              options([
                '国语',
                '英语',
                '粤语',
                '闽南语',
                '韩语',
                '日语',
                '法语',
                '德语',
                '其它',
                filters.language,
                ...all.expand((e) => catalogTokens(e.language))
              ]),
              (value) => change(filters.copyWith(language: value))),
          _filterRow('年份', filters.year, options(sortedYears),
              (value) => change(filters.copyWith(year: value))),
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('筛选当前已加载 ${feed.entries.length} 部 · 匹配 $count 部',
                        style: const TextStyle(fontSize: 11, color: _muted)),
                    const Text('加载更多可继续筛选；最新按来源更新时间，非小柚子同源片单。',
                        style: TextStyle(fontSize: 10, color: _muted)),
                    if (!hot || !rated)
                      Text(
                          '${[
                            if (!hot) '热度',
                            if (!rated) '评分'
                          ].join('、')}暂无可用数据，对应排序暂不可用',
                          style: const TextStyle(fontSize: 10, color: _muted)),
                    if (filters.order == CatalogOrder.popular)
                      const Text('按来源点击量排序，不是平台热度榜',
                          style: TextStyle(fontSize: 10, color: _muted)),
                    TextButton(
                        onPressed: () => change(const CatalogFilters()),
                        child: const Text('重置筛选')),
                  ])),
        ]));
  }

  Widget _rankings() => Column(children: [
        _tabs(rankingTabs, ranking, (label) {
          setState(() => ranking = label);
          browse.ensureLabel(label);
        }, dark: true),
        _sourcePicker(dark: true),
        Expanded(
            child: RefreshIndicator(
                onRefresh: () async {
                  await browse.refresh();
                  await browse.ensureLabel(ranking);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  key: PageStorageKey('ranking-$ranking'),
                  padding: const EdgeInsets.only(top: 8, bottom: 20),
                  children: [
                    !browse.hasSources
                        ? _emptySources()
                        : _categoryContent(ranking, ranked: true)
                  ],
                ))),
      ]);

  Widget _tabs(List<String> labels, String current, ValueChanged<String> onTap,
          {bool dark = false}) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(children: [
          for (final label in labels)
            TextButton(
                onPressed: () => onTap(label),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  foregroundColor: dark
                      ? Colors.white
                      : (label == current ? _ink : const Color(0xff666666)),
                ),
                child: Text(label,
                    style: TextStyle(
                        fontSize: label == current ? 16 : 14,
                        fontWeight: label == current
                            ? FontWeight.bold
                            : FontWeight.normal))),
        ]),
      );

  Widget _emptySources() =>
      _Feedback(message: '没有启用的内容源', action: '前往设置', onTap: _settings);

  Widget _profile() {
    final recent = widget.library.recentEntries.take(10).toList();
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 36, 16, 24),
        children: [
          const Center(
              child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.account_circle,
                      color: Color(0xffbbbbbb), size: 50))),
          const SizedBox(height: 10),
          const Center(
              child: Text('本地观影',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
          const SizedBox(height: 5),
          const Center(
              child: Text('收藏与历史仅保存在本机',
                  style: TextStyle(color: _muted, fontSize: 11))),
          const SizedBox(height: 22),
          _whitePanel(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _SectionHeader(title: '观看历史', onTap: _history, inset: 0),
            if (recent.isEmpty)
              const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text('还没有观看记录，去首页发现喜欢的内容吧',
                      style: TextStyle(color: _muted, fontSize: 12)))
            else
              SizedBox(
                  height: 92 + MediaQuery.textScalerOf(context).scale(12) * 4.3,
                  child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: recent.length,
                      separatorBuilder: (_, index) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final entry = recent[index];
                        final episode =
                            widget.library.lastWatchedEpisode(entry);
                        final progress = episode == null
                            ? const WatchProgress()
                            : widget.library.watchProgress(entry.id, episode);
                        return SizedBox(
                            width: 128,
                            child: Tooltip(
                                message: widget.library.watchSummary(entry),
                                child: InkWell(
                                    onTap: () => _detail(entry),
                                    child: Column(children: [
                                      ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(5),
                                          child: SizedBox(
                                              height: 72,
                                              width: 128,
                                              child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    _Poster(entry: entry),
                                                    if (episode != null)
                                                      Positioned(
                                                          right: 4,
                                                          bottom: 5,
                                                          child: Container(
                                                              padding: const EdgeInsets.symmetric(
                                                                  horizontal: 4,
                                                                  vertical: 1),
                                                              decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .black54,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                          3)),
                                                              child: Text(
                                                                  progress.completed
                                                                      ? '已看完'
                                                                      : WatchProgress.time(
                                                                          progress
                                                                              .positionMs),
                                                                  style: const TextStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontSize: 10)))),
                                                    Positioned(
                                                        left: 0,
                                                        right: 0,
                                                        bottom: 0,
                                                        child: LinearProgressIndicator(
                                                            minHeight: 2,
                                                            value: (progress
                                                                        .percent ??
                                                                    0) /
                                                                100)),
                                                  ]))),
                                      const SizedBox(height: 5),
                                      Text(entry.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11)),
                                      Text(
                                          [
                                            entry.source,
                                            if (episode != null) episode.name
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 10, color: _muted)),
                                      Text(
                                          episode == null
                                              ? '暂无分集进度'
                                              : progress.completed
                                                  ? '已看完 · 100%'
                                                  : progress.percent == null
                                                      ? progress.label
                                                      : '已观看 ${progress.percent}%',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 10, color: _orange)),
                                    ]))));
                      })),
          ])),
          const SizedBox(height: 12),
          _whitePanel(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _SectionHeader(title: '常用功能', inset: 0),
            LayoutBuilder(builder: (context, constraints) {
              final actions = <(String, IconData, VoidCallback)>[
                (
                  '我的收藏',
                  Icons.star_outline,
                  () => _open('我的收藏',
                      _SavedEntries(library: widget.library, favorites: true))
                ),
                ('我的下载', Icons.downloading_outlined, _downloads),
                ('观看历史', Icons.history, _history),
                ('设置', Icons.settings_outlined, _settings),
                ('直链播放', Icons.play_circle_outline, _search),
                (
                  '关于柚影',
                  Icons.info_outline,
                  () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                            title: const Text('柚影'),
                            content: const Text(
                                '独立媒体客户端。无账号、无广告。\n内容由第三方源提供，请仅访问有权使用的内容。\n当前排行榜为源更新列表，不代表真实热度。'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('知道了'))
                            ],
                          ))
                ),
              ];
              return Wrap(children: [
                for (final (label, icon, action) in actions)
                  SizedBox(
                      width: constraints.maxWidth / 4,
                      height: 84,
                      child: InkWell(
                          onTap: action,
                          borderRadius: BorderRadius.circular(8),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(icon,
                                    size: 24,
                                    color: label == '我的下载'
                                        ? _orange
                                        : const Color(0xff666666)),
                                const SizedBox(height: 10),
                                Text(label,
                                    style: const TextStyle(fontSize: 11)),
                              ]))),
              ]);
            }),
          ])),
        ]);
  }

  Widget _continueWatching() {
    final entry = widget.library.history.values.last;
    return Material(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: SizedBox(
          height: 48,
          child: Row(children: [
            const SizedBox(width: 8),
            const Icon(Icons.history, size: 18, color: _muted),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12)),
                  Text(widget.library.watchSummary(entry),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: _muted)),
                ])),
            TextButton(
                onPressed: () => _detail(entry),
                child: const Text('继续观看', style: TextStyle(fontSize: 12))),
            IconButton(
                tooltip: '关闭继续观看',
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => setState(() => hideContinue = true)),
          ])),
    );
  }
}

Widget _whitePanel(Widget child) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12)),
    child: child);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onTap, this.inset = 12});
  final String title;
  final VoidCallback? onTap;
  final double inset;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(inset, 16, inset, 12),
        child: InkWell(
            onTap: onTap,
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600))),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: _muted, size: 18),
            ])),
      );
}

class _Feedback extends StatelessWidget {
  const _Feedback({required this.message, this.action, this.onTap});
  final String message;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const Icon(Icons.movie_filter_outlined, size: 32, color: _muted),
        const SizedBox(height: 10),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 13)),
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ]));
}

class _FeedLoading extends StatelessWidget {
  const _FeedLoading();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))));
}

class _Poster extends StatelessWidget {
  const _Poster(
      {required this.entry,
      this.fit = BoxFit.cover,
      this.landscape = false,
      this.fallback});
  final MediaEntry entry;
  final BoxFit fit;
  final bool landscape;
  final Widget? fallback;
  @override
  Widget build(BuildContext context) {
    final placeholder = fallback ??
        ColoredBox(
            color: const Color(0xffe8e8e8),
            child: Center(
                child: Icon(Icons.movie_outlined,
                    size: 28, color: Colors.grey.shade400)));
    final urls =
        landscape ? catalogImageUrls([entry.backdrop]) : entry.posterCandidates;
    Widget imageAt(int index) {
      if (index >= urls.length) return placeholder;
      return Image.network(urls[index],
          key: ValueKey(urls[index]),
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          excludeFromSemantics: true,
          cacheWidth: landscape ? 1200 : 600,
          errorBuilder: (_, error, stack) => imageAt(index + 1),
          loadingBuilder: (_, child, loading) =>
              loading == null ? child : placeholder);
    }

    return imageAt(0);
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.entry, required this.onTap});
  final MediaEntry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: AspectRatio(
                aspectRatio: .68,
                child: Stack(fit: StackFit.expand, children: [
                  _Poster(entry: entry),
                  if (entry.remarks.isNotEmpty)
                    Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(4, 16, 4, 5),
                            decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                  Colors.transparent,
                                  Colors.black87
                                ])),
                            child: Text(entry.remarks,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.white)))),
                ]))),
        const SizedBox(height: 6),
        Text(entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12)),
      ]));
}

class _PosterStrip extends StatelessWidget {
  const _PosterStrip({required this.entries, required this.onTap});
  final List<MediaEntry> entries;
  final ValueChanged<MediaEntry> onTap;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = ((constraints.maxWidth - 40) / 5).clamp(64.0, 110.0);
        return SizedBox(
            height: width / .68 +
                MediaQuery.textScalerOf(context).scale(12) * 1.5 +
                10,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, index) => const SizedBox(width: 4),
              itemBuilder: (_, index) => SizedBox(
                  width: width,
                  child: _PosterTile(
                      entry: entries[index],
                      onTap: () => onTap(entries[index]))),
            ));
      });
}

class _Spotlight extends StatefulWidget {
  const _Spotlight({super.key, required this.entries, required this.onTap});
  final List<MediaEntry> entries;
  final ValueChanged<MediaEntry> onTap;
  @override
  State<_Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<_Spotlight> {
  int selected = 0;
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: AspectRatio(
            aspectRatio: 3,
            child: Stack(children: [
              PageView.builder(
                  itemCount: widget.entries.length,
                  onPageChanged: (index) => setState(() => selected = index),
                  itemBuilder: (_, index) {
                    final entry = widget.entries[index];
                    return InkWell(
                        onTap: () => widget.onTap(entry),
                        child: Stack(fit: StackFit.expand, children: [
                          _SpotlightArtwork(entry: entry),
                          const DecoratedBox(
                              decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                Colors.transparent,
                                Colors.black54
                              ]))),
                          Positioned(
                              left: 10,
                              right: 60,
                              bottom: 12,
                              child: Text(entry.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14))),
                        ]));
                  }),
              Positioned(
                  right: 10,
                  bottom: 14,
                  child: Row(children: [
                    for (var i = 0; i < widget.entries.length; i++)
                      Container(
                          width: i == selected ? 12 : 4,
                          height: 4,
                          margin: const EdgeInsets.only(left: 3),
                          decoration: BoxDecoration(
                              color: i == selected ? _orange : Colors.white60,
                              borderRadius: BorderRadius.circular(4))),
                  ])),
            ])),
      );
}

class _SpotlightArtwork extends StatelessWidget {
  const _SpotlightArtwork({required this.entry});
  final MediaEntry entry;

  @override
  Widget build(BuildContext context) => ColoredBox(
      color: const Color(0xff272936),
      child: _Poster(
          entry: entry,
          landscape: true,
          fit: BoxFit.contain,
          fallback: Row(children: [
            AspectRatio(
                aspectRatio: .68,
                child: _Poster(entry: entry, fit: BoxFit.contain)),
            Expanded(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 36),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                            [entry.year, entry.area, entry.remarks]
                                .where((value) => value.isNotEmpty)
                                .join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12))))),
          ])));
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard(
      {required this.entry,
      required this.onTap,
      this.trailing,
      this.watchInfo});
  final MediaEntry entry;
  final VoidCallback onTap;
  final Widget? trailing;
  final String? watchInfo;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 66,
                    height: 99,
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: _Poster(entry: entry))),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                          [entry.source, entry.year, entry.category, entry.area]
                              .where((s) => s.isNotEmpty)
                              .join(' / '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: _muted)),
                      const SizedBox(height: 6),
                      Text(
                          watchInfo ??
                              (entry.description.isEmpty
                                  ? (entry.remarks.isEmpty
                                      ? '暂无简介'
                                      : entry.remarks)
                                  : entry.description),
                          maxLines: watchInfo == null ? 2 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, height: 1.4, color: _muted)),
                      const SizedBox(height: 6),
                      SizedBox(
                          height: 19,
                          child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                for (final actor in entry.actors
                                    .split(RegExp(r'[,，/、]'))
                                    .where((s) => s.trim().isNotEmpty)
                                    .take(5))
                                  Container(
                                      margin: const EdgeInsets.only(right: 5),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: _canvas,
                                          borderRadius:
                                              BorderRadius.circular(2)),
                                      child: Text(actor.trim(),
                                          style: const TextStyle(
                                              fontSize: 10, color: _muted))),
                              ])),
                    ])),
                if (trailing != null) trailing!,
              ])),
        ),
      );
}

class _SavedEntries extends StatelessWidget {
  const _SavedEntries({required this.library, this.favorites = false});
  final Library library;
  final bool favorites;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: library,
      builder: (context, _) {
        final entries = favorites
            ? library.favorites.values.toList().reversed.toList()
            : library.recentEntries;
        if (entries.isEmpty) {
          return _Feedback(
              message: favorites ? '还没有收藏，去详情页收藏喜欢的内容吧' : '还没有观看历史');
        }
        return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, index) => const SizedBox(height: 12),
            itemBuilder: (_, index) {
              final entry = entries[index];
              return _CatalogCard(
                  entry: entry,
                  watchInfo: favorites ? null : library.watchSummary(entry),
                  trailing: favorites
                      ? IconButton(
                          tooltip: '取消收藏',
                          icon:
                              const Icon(Icons.star, color: _orange, size: 20),
                          onPressed: () => library.toggleFavorite(entry))
                      : null,
                  onTap: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              DetailPage(entry: entry, library: library))));
            });
      });
}
