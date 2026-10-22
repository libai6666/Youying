import 'catalog.dart';

const sourcePresetRepository = 'https://github.com/Stardm0/MoonTV\n'
    'https://github.com/vodtv/api\n'
    'https://github.com/cms-player/vod-source\n'
    'https://gist.github.com/alinuxsa/5d3f69983fe96b0d815a49f9f569556e';
const sourcePresetCheckedOn = '2026-10-22';

const retiredSourcePresetUrls = {
  'https://api.wujinapi.me/api.php/provide/vod',
  'https://cj.lzcaiji.com/api.php/provide/vod',
};

class SourcePreset {
  const SourcePreset(this.source, this.observation,
      {this.introducedIn = 1, this.localSearchCategories = const []});
  final SourceEndpoint source;
  final String observation;
  final int introducedIn;

  /// Category IDs indexed in-app when the source rejects keyword search.
  final List<String> localSearchCategories;
}

const sourcePresets = [
  SourcePreset(
    SourceEndpoint(
        name: '360资源', url: 'https://360zyzz.com/api.php/provide/vod'),
    '目录/片单/搜索/详情/图片及 HLS 清单抽样通过；播放/完整下载未验收',
  ),
  SourcePreset(
    SourceEndpoint(
        name: '极速资源', url: 'https://jszyapi.com/api.php/provide/vod'),
    '目录/片单/详情/图片及 HLS 清单通过；指定片名搜索一次失败；播放未验收',
  ),
  SourcePreset(
    SourceEndpoint(
        name: '猫眼资源（第三方）',
        url: 'https://api.maoyanapi.top/api.php/provide/vod'),
    '目录/片单/搜索/详情请求通过；媒体清单抽样失败；非猫眼官方；播放未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '豪华资源', url: 'https://hhzyapi.com/api.php/provide/vod'),
    '片单/搜索/详情/图片及 HLS 清单通过；分类一次失败；播放未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '光速资源', url: 'https://api.guangsuapi.com/api.php/provide/vod'),
    '目录/片单/搜索/详情/图片及 HLS 清单抽样通过；播放/完整下载未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '如意资源', url: 'https://cj.rycjapi.com/api.php/provide/vod'),
    '目录/片单/搜索/详情/图片及 HLS 清单抽样通过；播放/完整下载未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '红牛资源', url: 'https://www.hongniuzy2.com/api.php/provide/vod'),
    '目录/片单/搜索/详情/图片及 HLS 清单抽样通过；播放/完整下载未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '魔都资源', url: 'https://www.mdzyapi.com/api.php/provide/vod'),
    '见 MoonTV 与 vodtv/api 公共配置；目录/片单/搜索/详情/图片及 HLS 清单抽样通过；播放未验收',
    introducedIn: 3,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '无水印资源', url: 'https://api.wsyzy.net/api.php/provide/vod'),
    '漫剧 339 部、反转爽剧 4681 部，本机抽样 12 部 HTTPS 清单/分片/海报通过、无加密；服务端不支持关键词搜索，App 内按片名检索',
    introducedIn: 4,
    localSearchCategories: ['65', '76'],
  ),
  SourcePreset(
    SourceEndpoint(
        name: 'iKun资源', url: 'https://ikunzyapi.com/api.php/provide/vod'),
    '爽文短剧 1511 部，HLS 主清单 1080p 约 2.3Mbps；目录/片单/搜索抽样通过；播放/完整下载未验收',
    introducedIn: 5,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '索尼资源', url: 'https://suoniapi.com/api.php/provide/vod'),
    '漫剧 5540 部、反转爽剧 4655 部，HLS 主清单 1080p；目录/片单抽样通过；服务端不支持关键词搜索，App 内按片名检索；播放未验收',
    introducedIn: 5,
    localSearchCategories: ['65', '76'],
  ),
  SourcePreset(
    SourceEndpoint(
        name: '闪电资源', url: 'https://xsd.sdzyapi.com/api.php/provide/vod'),
    '反转爽剧 3964 部，HLS 主清单 1080p；目录/片单抽样通过；服务端不支持关键词搜索，App 内按片名检索；播放未验收',
    introducedIn: 5,
    localSearchCategories: ['54', '65', '75'],
  ),
  SourcePreset(
    SourceEndpoint(
        name: '最大资源', url: 'https://api.zuidapi.com/api.php/provide/vod'),
    '目录/片单/搜索抽样通过；HLS 主清单 1080p；播放/完整下载未验收',
    introducedIn: 5,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '牛牛资源', url: 'https://api.niuniuzy.me/api.php/provide/vod/'),
    '反转爽剧 3450 部、爽文短剧 1080 部，HLS 主清单 1080p；目录/片单抽样通过；服务端不支持关键词搜索，App 内按片名检索；播放未验收',
    introducedIn: 5,
    localSearchCategories: ['54', '65', '75'],
  ),
  SourcePreset(
    SourceEndpoint(
        name: '丫丫资源', url: 'https://cj.yayazy.net/api.php/provide/vod'),
    '反转爽剧 3378 部、爽文短剧 884 部，HLS 主清单 1080p；目录/片单抽样通过；服务端不支持关键词搜索，App 内按片名检索；播放未验收',
    introducedIn: 5,
    localSearchCategories: ['54', '65', '75'],
  ),
  SourcePreset(
    SourceEndpoint(
        name: '快车资源', url: 'https://caiji.kuaichezy.org/api.php/provide/vod'),
    '反转爽剧 3888 部，HLS 主清单 1080p；目录/片单抽样通过；服务端不支持关键词搜索，App 内按片名检索；播放未验收',
    introducedIn: 5,
    localSearchCategories: ['54', '65', '75'],
  ),
];

SourcePreset? presetFor(SourceEndpoint source) {
  for (final preset in sourcePresets) {
    if (preset.source.url == source.url) return preset;
  }
  return null;
}
