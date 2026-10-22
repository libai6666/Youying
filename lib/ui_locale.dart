import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

const appLocales = [Locale('zh', 'CN'), Locale('en', 'US')];
const appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  _UiLocaleDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

class _UiLocale {
  const _UiLocale(this.locale);
  final Locale locale;
}

class _UiLocaleDelegate extends LocalizationsDelegate<_UiLocale> {
  const _UiLocaleDelegate();
  @override
  bool isSupported(Locale locale) =>
      const ['zh', 'en'].contains(locale.languageCode);
  @override
  Future<_UiLocale> load(Locale locale) => SynchronousFuture(_UiLocale(locale));
  @override
  bool shouldReload(_UiLocaleDelegate old) => false;
}

const _english = <String, String>{
  '集': 'episodes',
  '柚影': 'Youying',
  '无法读取本地数据': 'Could not read local data',
  '首页': 'Home',
  '排行榜': 'Rankings',
  '我的': 'Me',
  '搜索': 'Search',
  '设置': 'Settings',
  '观看历史': 'Watch history',
  '我的下载': 'Downloads',
  '我的收藏': 'Favorites',
  '电影': 'Movies',
  '电视剧': 'TV series',
  '综艺': 'Variety',
  '动漫': 'Anime',
  '二次元动漫': 'Anime',
  '热门短剧': 'Short dramas',
  '短剧': 'Short dramas',
  'AI漫剧': 'AI animation',
  'AI短剧': 'AI short dramas',
  '电视直播': 'Live TV',
  '全部': 'All',
  '请输入关键字': 'Search titles',
  '搜索影片、电视剧、动漫': 'Search movies, series, anime',
  '输入片名，搜索已启用的内容来源': 'Enter a title to search enabled sources',
  '输入关键词并点击搜索。': 'Enter a keyword and tap Search.',
  '正在寻找匹配内容…': 'Searching for matches…',
  '暂无匹配内容，试试其他片名或分类。': 'No matches. Try another title or category.',
  '热播剧推荐': 'Recently updated series',
  '热播综艺': 'Recently updated variety',
  '热播动漫': 'Recently updated anime',
  '聚合更新顺序 · 非热度榜': 'Source update order · not a popularity chart',
  '更新推荐 · 非平台热度': 'Recent updates · not platform popularity',
  '重试分类': 'Retry categories',
  '重试': 'Retry',
  '加载': 'Load',
  '部分内容来源暂时不可用': 'Some sources are temporarily unavailable',
  '部分来源加载失败': 'Some sources failed to load',
  '重试未完成来源': 'Retry failed sources',
  '加载更多': 'Load more',
  '上滑加载更多': 'Scroll up to load more',
  '没有更多了': 'No more items',
  '暂未取得内容，可在更多中继续加载': 'Nothing yet. Load more to continue.',
  '暂未取得内容，可继续加载其他子分类': 'No results yet. Load another category.',
  '当前已加载内容没有匹配项，可调整筛选或继续上滑加载':
      'No matches in loaded results. Adjust filters or load more.',
  '该分类暂无内容': 'Nothing in this category',
  '当前为点播源，未接入电视直播': 'Live TV is not available from on-demand sources',
  '点击加载该分类': 'Tap to load this category',
  '排序': 'Sort',
  '最新': 'Latest',
  '最热': 'Popular',
  '好评': 'Top rated',
  '类型': 'Genre',
  '题材': 'Theme',
  '题材按片名和简介推断，仅供参考': 'Themes are inferred from titles and synopses',
  '穿越': 'Time travel',
  '重生': 'Rebirth',
  '甜宠': 'Sweet romance',
  '逆袭': 'Comeback',
  '玄幻仙侠': 'Fantasy & xianxia',
  '末世': 'Apocalypse',
  '系统': 'System',
  '萌宝': 'Cute kids',
  '地区': 'Region',
  '语言': 'Language',
  '年份': 'Year',
  '热度': 'Popularity',
  '评分': 'Rating',
  '重置筛选': 'Reset filters',
  '没有启用的内容源': 'No sources enabled',
  '前往设置': 'Open settings',
  '继续上滑会加载更多内容；最新按来源更新时间，非小柚子同源片单。':
      'Load more to filter more titles. Latest is based on source updates.',
  '按来源点击量排序，不是平台热度榜': 'Ordered by source views, not platform popularity',
  '本地观影': 'Your library',
  '收藏与历史仅保存在本机': 'Favorites and history stay on this device',
  '还没有观看记录，去首页发现喜欢的内容吧': 'No watch history. Browse titles on Home.',
  '还没有收藏，去详情页收藏喜欢的内容吧': 'No favorites. Save titles from their details.',
  '还没有观看历史': 'No watch history',
  '常用功能': 'Quick actions',
  '直链播放': 'Play a direct URL',
  '关于柚影': 'About Youying',
  '知道了': 'Got it',
  '继续观看': 'Continue watching',
  '关闭继续观看': 'Dismiss continue watching',
  '暂无简介': 'No description',
  '暂无分集进度': 'No episode progress',
  '已看完': 'Finished',
  '已看完 · 100%': 'Finished · 100%',
  '搜索结果': 'Search results',
  '搜索历史': 'Search history',
  '清空搜索历史？': 'Clear search history?',
  '仅删除搜索关键词，不影响观看记录和下载。':
      'Only search terms are removed. Watch history and downloads stay.',
  '清空': 'Clear',
  '取消': 'Cancel',
  '删除': 'Delete',
  '来源状态': 'Source status',
  '来源设置已变化，请重新搜索': 'Sources changed. Search again.',
  '正在搜索已启用的源…': 'Searching enabled sources…',
  '直接播放你有权访问的媒体': 'Play media you are allowed to access',
  'HTTPS 媒体地址（MP4 / HLS / DASH）': 'HTTPS media URL (MP4 / HLS / DASH)',
  '请求头 JSON（可空，不保存）': 'Request headers JSON (optional, not saved)',
  '播放': 'Play',
  '暂停': 'Pause',
  '重播': 'Replay',
  '手动播放直链': 'Play a direct URL',
  '手动输入的媒体': 'Manually entered media',
  '请输入有效的 HTTPS URL 和 JSON 格式请求头':
      'Enter a valid HTTPS URL and JSON request headers',
  '收藏': 'Favorite',
  '取消收藏': 'Remove favorite',
  '查找更多播放源': 'Find more sources',
  '换源': 'Change source',
  '演员': 'Cast',
  '导演': 'Director',
  '时长': 'Duration',
  '剧情简介': 'Synopsis',
  '播放来源': 'Playback source',
  '正在匹配…': 'Finding versions…',
  '正在加载播放资源…': 'Loading playback…',
  '重试详情': 'Retry details',
  '详情请求失败；已保留现有线路，可重试':
      'Details failed. Existing playback remains available; retry.',
  '播放资源加载失败，请重试或换源': 'Playback failed. Retry or change source.',
  '当前来源暂无可播放视频，请换源': 'No playable video from this source. Try another.',
  '添加你信任的源': 'Add a source you trust',
  '名称': 'Name',
  'HTTPS JSON 接口': 'HTTPS JSON endpoint',
  '保存': 'Save',
  '源配置': 'Sources',
  '添加源': 'Add source',
  '播放设置': 'Playback settings',
  '自动续播下一集': 'Auto-play next episode',
  '播放结束后等待 3 秒，继续播放当前线路的下一集':
      'Wait 3 seconds, then play the next episode on this line',
  '下载设置': 'Download settings',
  '下载并发数': 'Concurrent downloads',
  '默认 3 个，最多 10 个；按剧集任务计数': 'Default 3, maximum 10; counted per episode',
  '恢复范围': 'Reconstruction scope',
  '播放器仅在 Android 上提供': 'The player is available only on Android',
  '只播放 HTTPS 媒体或已下载文件': 'Play HTTPS media or downloaded files only',
  '无法初始化 Android 播放器': 'Could not initialize Android player',
  '播放失败，请检查地址、格式和网络': 'Playback failed. Check the URL, format and network.',
  '没有该集的已下载文件': 'No downloaded file for this episode',
  '播放地址不可用': 'Playback URL unavailable',
  '本线路已播完': 'Playback line finished',
  '本集已播完': 'Episode finished',
  '长按 2.0x 播放': 'Hold for 2.0x playback',
  '取消续播': 'Cancel auto-play',
  '退出全屏': 'Exit fullscreen',
  '切换线路': 'Change line',
  '清晰度': 'Quality',
  '自动': 'Auto',
  '无法切换清晰度': 'Could not switch quality',
  '仅一条线路': 'Only one line',
  '选集': 'Episodes',
  '下载剧集': 'Download episodes',
  '详情介绍': 'Details',
  '播放下一集': 'Next episode',
  '投屏': 'Cast',
  '选择投屏设备': 'Choose a casting device',
  '未发现设备，请确认电视与手机在同一网络后重试':
      'No devices found — make sure the TV and phone share a network, then retry',
  '投屏失败，请重试': 'Casting failed, please retry',
  '重新搜索': 'Search again',
  '播放上一集': 'Previous episode',
  '上一个频道': 'Previous channel',
  '下一个频道': 'Next channel',
  '倍速': 'Speed',
  '全屏': 'Fullscreen',
  '返回原资源': 'Return to original title',
  '播放已下载文件': 'Play downloaded file',
  '全部剧集': 'All episodes',
  '切换正序': 'Oldest first',
  '切换倒序': 'Newest first',
  '倒序': 'Newest first',
  '正序': 'Oldest first',
  '关闭全部剧集': 'Close episodes',
  '已完成': 'Completed',
  '加入中…': 'Adding…',
  '全部开始': 'Start all',
  '查看下载列表': 'View downloads',
  '删除下载？': 'Delete download?',
  '下载任务操作失败，请重试': 'Download operation failed. Retry.',
  '正在下载': 'Downloading',
  '该影片已无下载任务': 'No download tasks for this title',
  '暂无下载任务': 'No download tasks',
  '原资源': 'Original title',
  '离线播放': 'Play offline',
  '继续': 'Resume',
  '全部暂停': 'Pause all',
  '全部继续': 'Resume all',
  '全部删除': 'Delete all',
  '删除全部下载？': 'Delete all downloads?',
  '取消全选': 'Deselect all',
  '全选': 'Select all',
  '下载剧集排序': 'Download order',
  '关闭下载选集': 'Close episode picker',
  '热度暂无可用数据，对应排序暂不可用': 'Popularity data unavailable; sorting is disabled.',
  '评分暂无可用数据，对应排序暂不可用': 'Rating data unavailable; sorting is disabled.',
  '目录/片单/搜索/详情/图片及 HLS 清单抽样通过；播放/完整下载未验收':
      'Sampled catalog, listings, search, details, images and HLS passed. Playback and full downloads not verified.',
  '目录/片单/详情/图片及 HLS 清单通过；指定片名搜索一次失败；播放未验收':
      'Sampled catalog, listings, details, images and HLS passed. One title search failed. Playback not verified.',
  '目录/片单/搜索/详情请求通过；媒体清单抽样失败；非猫眼官方；播放未验收':
      'Catalog, listings, search and details responded. Sample media playlist failed. Not an official Maoyan API. Playback not verified.',
  '片单/搜索/详情/图片及 HLS 清单通过；分类一次失败；播放未验收':
      'Sampled listings, search, details, images and HLS passed. One category request failed. Playback not verified.',
  '见 MoonTV 与 vodtv/api 公共配置；目录/片单/搜索/详情/图片及 HLS 清单抽样通过；播放未验收':
      'Listed by MoonTV and vodtv/api. Sampled catalog, listings, search, details, images and HLS passed. Playback not verified.',
  '中国大陆': 'Mainland China',
  '内地': 'Mainland China',
  '大陆': 'Mainland China',
  '香港': 'Hong Kong',
  '中国香港': 'Hong Kong',
  '台湾': 'Taiwan',
  '中国台湾': 'Taiwan',
  '美国': 'US',
  '法国': 'France',
  '英国': 'UK',
  '日本': 'Japan',
  '韩国': 'South Korea',
  '德国': 'Germany',
  '泰国': 'Thailand',
  '汉语普通话': 'Mandarin',
  '普通话': 'Mandarin',
  '国语': 'Mandarin',
  '英语': 'English',
  '粤语': 'Cantonese',
  '闽南语': 'Hokkien',
  '韩语': 'Korean',
  '日语': 'Japanese',
  '法语': 'French',
  '德语': 'German',
  '其它': 'Other',
  '喜剧': 'Comedy',
  '爱情': 'Romance',
  '恐怖': 'Horror',
  '动作': 'Action',
  '科幻': 'Sci-fi',
  '剧情': 'Drama',
  '战争': 'War',
  '悬疑': 'Mystery',
  '犯罪': 'Crime',
  '动画': 'Animation',
  '纪录': 'Documentary',
  '古装': 'Costume',
  '都市': 'Urban',
  '家庭': 'Family',
  '武侠': 'Wuxia',
  '玄幻': 'Xuanhuan',
  '奇幻': 'Fantasy',
  '冒险': 'Adventure',
  '搞笑': 'Comedy',
  '恋爱': 'Romance',
  '校园': 'School',
  '热血': 'Action',
  '真人秀': 'Reality',
  '音乐': 'Music',
  '脱口秀': 'Talk show',
  '舞蹈': 'Dance',
  '访谈': 'Interviews',
  '生活': 'Lifestyle',
  '国产剧': 'Chinese series',
  '欧美剧': 'Western series',
  '日本剧': 'Japanese series',
  '韩国剧': 'Korean series',
  '台湾剧': 'Taiwanese series',
  '香港剧': 'Hong Kong series',
  '下载中': 'Downloading',
  '等待网络': 'Waiting for network',
  '排队中': 'Queued',
  '已暂停': 'Paused',
  '删除中': 'Removing',
  '下载失败': 'Download failed',
  '等待中': 'Waiting',
  '未观看 · 0%': 'Unwatched · 0%',
  '内容目录暂时不可用，请重试或检查源设置': 'Catalog unavailable. Retry or check source settings.',
  '分类请求失败': 'Category request failed',
  '分类目录暂不可用，请刷新或查看来源状态':
      'Categories unavailable. Refresh or check source status.',
  '内容请求失败，可重试': 'Content request failed. Retry.',
  '本批内容加载失败，请重试': 'This batch failed to load. Retry.',
  '没有启用的源，请在“设置”中启用或添加。': 'No sources enabled. Enable or add one in Settings.',
  '可选 Referer / User-Agent 等请求头只用于本次播放。':
      'Optional Referer / User-Agent headers apply only to this playback.',
  '搜索历史保存失败，请重试；不影响搜索': 'Could not save search history. Search is unaffected.',
  '源配置保存失败，请检查输入并重试': 'Could not save source. Check the input and retry.',
  '自动续播设置保存失败，请重试': 'Could not save auto-play setting. Retry.',
  '下载并发数保存失败，请重试': 'Could not save download limit. Retry.',
  '兼容 HTTPS JSON 点播接口；启用后用于首页分类、列表、搜索和详情。':
      'Supports HTTPS JSON on-demand APIs for categories, listings, search and details.',
  '公开源由 GitHub 配置收录，不等于内容授权或长期可用。升级补充新源并清理退役预设；保留自定义接口和启停状态，删除后不会自动恢复。':
      'Public GitHub listings do not establish content rights or reliability. Updates may add new presets and retire failed ones. Custom URLs and enabled states are kept; removed presets are not restored.',
  '停用后不再发起该源的搜索/详情请求；不取消已开始的请求或播放。':
      'Disabling stops new requests, but not requests or playback already in progress.',
  '用户手动配置；未验证': 'User configured; not verified',
  '支持来源允许保存的普通文件与 AES-128 HLS 点播。DRM 需平台授权离线许可；直播暂不支持。任务与缓存保存在应用私有目录，暂停与重启后可继续。':
      'Downloads files and AES-128 HLS where saving is permitted. DRM needs an authorized offline license; live streams are unsupported. Tasks and cache are private to the app and can resume after pausing or restarting.',
  '来自原 APK 的确认项：Flutter/Dart AOT 字符串与安卓 Media3 播放器接口。播放器 Android 实现、界面、收藏、历史、Media3 离线下载和 JSON 列表兼容器均为新写代码。':
      'Confirmed from the original APK: Flutter/Dart AOT strings and Android Media3 interfaces. The Android player, UI, favorites, history, offline downloads and JSON adapter are independently rewritten.',
  '不包含：未知服务端、完整原始 Dart、原本的解析/下载加密逻辑、广告与统计 SDK。':
      'Does not include unknown backends, original Dart source, original parsing/encryption logic, ads or analytics SDKs.',
  '独立媒体客户端。无账号、无广告。\n内容由第三方源提供，请仅访问有权使用的内容。\n当前排行榜为源更新列表，不代表真实热度。':
      'Independent media client. No account or ads.\nThird-party sources provide content; access only content you have rights to.\nRankings show source update order, not measured popularity.',
  '无法调整播放进度': 'Could not seek',
  '无法切换播放速度': 'Could not change speed',
  '无法继续播放': 'Could not resume playback',
  '当前只有一条播放线路；可点右侧“换源”查找其他来源':
      'Only one playback line. Use Change source to find another.',
  '这些剧集已有任务，请在下载列表中继续或重试':
      'These episodes already have tasks. Resume or retry in Downloads.',
  '加入下载任务失败，请重试': 'Could not add download tasks. Retry.',
  '离线服务尚不可用，请重新启动包含原生更新的调试包':
      'Offline service unavailable. Restart a debug build with the native updates.',
  '旧版已下载文件（在对应影片中选择“播放已下载文件”）':
      'Legacy downloads (open the title and choose Play downloaded file)',
  '已保存的本地视频': 'Saved local video',
  '该线路需要平台提供 DRM 离线许可，当前无法下载':
      'This line requires an authorized DRM offline license.',
  '该线路使用不支持的采样加密；普通 AES-128 HLS 可下载':
      'Unsupported sample encryption. Standard AES-128 HLS is supported.',
  '直播或未结束的 HLS 不支持离线下载': 'Live or unfinished HLS cannot be downloaded.',
  '下载地址或分片必须使用 HTTPS': 'Download and segment URLs must use HTTPS.',
  'HLS 密钥声明格式无效，请更换线路': 'Invalid HLS key declaration. Try another line.',
  'HLS 清单超过大小限制': 'HLS playlist exceeds the size limit.',
  '请检查网络、来源下载授权或存储空间后重试':
      'Check network, source download permissions and free space, then retry.',
};

String uiText(BuildContext context, String value) {
  if (Localizations.of<_UiLocale>(context, _UiLocale)?.locale.languageCode !=
      'en') {
    return value;
  }
  final exact = _english[value];
  if (exact != null) return exact;
  for (final rule in _rules) {
    final match = rule.$1.firstMatch(value);
    if (match != null) return rule.$2(match);
  }
  for (final prefix in const {
    '主演：': 'Cast: ',
    '导演：': 'Director: ',
    '语言：': 'Language: ',
    '时长：': 'Duration: ',
    '观看进度：': 'Watch progress: ',
    '删除搜索记录：': 'Remove search: ',
  }.entries) {
    if (value.startsWith(prefix.key)) {
      final suffix = value.substring(prefix.key.length);
      return prefix.value +
          (prefix.key == '观看进度：' ? uiText(context, suffix) : suffix);
    }
  }
  if (value.endsWith('参与搜索')) {
    return 'Use ${value.substring(0, value.length - 4)} in searches';
  }
  if (value.startsWith('移除')) return 'Remove ${value.substring(2)}';
  if (value.startsWith('管理')) return 'Manage ${value.substring(2)}';
  if (value.endsWith('\n同时移除已缓存的离线内容。')) {
    return value.replaceFirst(
        '同时移除已缓存的离线内容。', 'Cached offline content will also be removed.');
  }
  if (value.startsWith('多源聚合 · ')) {
    return value
        .replaceFirst('多源聚合 · ', 'Multiple sources · ')
        .replaceFirst(' 个来源', ' enabled');
  }
  if (value.startsWith('已启用来源未提供“')) {
    return 'No enabled source offers ${uiText(context, value.substring(9, value.length - 3))}';
  }
  if (value.startsWith('筛选当前已加载 ')) {
    return value
        .replaceFirst('筛选当前已加载 ', 'Loaded ')
        .replaceFirst(' 部 · 匹配 ', ' titles · matching ')
        .replaceFirst(' 部', ' titles');
  }
  if (value.startsWith('已加载 ')) {
    return value
        .replaceFirst('已加载 ', 'Loaded ')
        .replaceFirst(' 部 · 全库约 ', ' titles · ~')
        .replaceFirst(' 部 · 匹配 ', ' in catalog · matching ')
        .replaceFirst(' 部', ' titles');
  }
  if (value.startsWith('找到 ') || value.startsWith('已搜索 ')) {
    return value
        .replaceAll('找到 ', 'Found ')
        .replaceAll('已搜索 ', 'Searched ')
        .replaceAll(' 部影片', ' titles')
        .replaceAll(' 个来源', ' sources')
        .replaceAll('暂不可用', 'unavailable');
  }
  return value;
}

final _rules = <(RegExp, String Function(RegExpMatch))>[
  (
    RegExp(r'^(\d{4}-\d{2}-\d{2}) 历史抽查：(.*)$'),
    (m) => '${m[1]} Sample check: ${_english[m[2]] ?? m[2]}'
  ),
  (
    RegExp(r'^共 (\d+) 个源，已启用 (\d+) 个。$'),
    (m) => '${m[1]} sources · ${m[2]} enabled'
  ),
  (RegExp(r'^(\d+) 个$'), (m) => '${m[1]}'),
  (RegExp(r'^(\d+) 秒后播放下一集$'), (m) => 'Next episode in ${m[1]} s'),
  (RegExp(r'^全部 (\d+) 集$'), (m) => 'All ${m[1]} episodes'),
  (RegExp(r'^已推送到 (.*)$'), (m) => 'Cast to ${m[1]}'),
  (RegExp(r'^下载 (\d+) 集$'), (m) => 'Download ${m[1]} episodes'),
  (
    RegExp(r'^已加入 (\d+) 集，请在下载列表查看进度$'),
    (m) => '${m[1]} episodes added. Check Downloads for progress.'
  ),
  (
    RegExp(r'^(.*) · 共 (\d+) 集 · 仅下载你有权保存的内容$'),
    (m) => '${m[1]} · ${m[2]} episodes · Download only with permission'
  ),
  (
    RegExp(r'^同时下载最多 (\d+) 集 · 可在设置中调整$'),
    (m) => 'Up to ${m[1]} simultaneous downloads · Change in Settings'
  ),
  (RegExp(r'^已缓存 (\d+) 集 · (.*)$'), (m) => '${m[1]} episodes cached · ${m[2]}'),
  (RegExp(r'^已观看 (\d+)% · (.*)$'), (m) => 'Watched ${m[1]}% · ${m[2]}'),
  (RegExp(r'^已观看 (\d+)%$'), (m) => 'Watched ${m[1]}%'),
  (RegExp(r'^已观看 (.*) · 比例待更新$'), (m) => 'Watched ${m[1]} · progress pending'),
  (RegExp(r'^(.*)：(\d+) 条$'), (m) => '${m[1]}: ${m[2]} results'),
  (
    RegExp(r'^(.*)：请求失败或返回格式不兼容$'),
    (m) => '${m[1]}: request failed or unsupported response'
  ),
  (RegExp(r'^已找到 (\d+) 个版本$'), (m) => '${m[1]} versions found'),
  (
    RegExp(r'^共 (\d+) 项任务\n同时移除已缓存的离线内容。$'),
    (m) => '${m[1]} tasks · Cached offline content will also be removed.'),
  (
    RegExp(r'^已找到 (\d+) 个版本，(\d+) 个来源暂不可用$'),
    (m) => '${m[1]} versions found · ${m[2]} sources unavailable'
  ),
];

class LocalizedText extends StatelessWidget {
  const LocalizedText(this.data,
      {super.key,
      this.style,
      this.maxLines,
      this.overflow,
      this.textAlign,
      this.softWrap,
      this.textDirection,
      this.semanticsLabel,
      this.textScaler});
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;
  final bool? softWrap;
  final TextDirection? textDirection;
  final String? semanticsLabel;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) => Text(uiText(context, data),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      softWrap: softWrap,
      textDirection: textDirection,
      semanticsLabel: semanticsLabel,
      textScaler: textScaler);
}
