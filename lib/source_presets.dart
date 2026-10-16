import 'catalog.dart';

const sourcePresetRepository = 'https://github.com/Stardm0/MoonTV\n'
    'https://github.com/vodtv/api\n'
    'https://github.com/cms-player/vod-source\n'
    'https://gist.github.com/alinuxsa/5d3f69983fe96b0d815a49f9f569556e';
const sourcePresetCheckedOn = '2026-10-16';

const retiredSourcePresetUrls = {
  'https://api.wujinapi.me/api.php/provide/vod',
  'https://cj.lzcaiji.com/api.php/provide/vod',
};

class SourcePreset {
  const SourcePreset(this.source, this.observation, {this.introducedIn = 1});
  final SourceEndpoint source;
  final String observation;
  final int introducedIn;
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
];

SourcePreset? presetFor(SourceEndpoint source) {
  for (final preset in sourcePresets) {
    if (preset.source.url == source.url) return preset;
  }
  return null;
}
