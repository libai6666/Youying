import 'catalog.dart';

const sourcePresetRepository = 'https://github.com/vodtv/api\n'
    'https://github.com/cms-player/vod-source\n'
    'https://gist.github.com/alinuxsa/5d3f69983fe96b0d815a49f9f569556e';
const sourcePresetCheckedOn = '2026-10-14';

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
    '本机搜索/详情/清单通过；抽查含加密分片，不支持下载；播放未验收',
  ),
  SourcePreset(
    SourceEndpoint(
        name: '极速资源', url: 'https://jszyapi.com/api.php/provide/vod'),
    '本机搜索/详情/清单通过；抽查含加密分片，不支持下载；播放未验收',
  ),
  SourcePreset(
    SourceEndpoint(
        name: '猫眼资源（第三方）',
        url: 'https://api.maoyanapi.top/api.php/provide/vod'),
    '本机搜索/详情/分类/首页/清单通过；抽查加密 HLS 不支持下载；非猫眼官方；播放未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '豪华资源', url: 'https://hhzyapi.com/api.php/provide/vod'),
    '本机搜索/详情/分类/首页/清单通过；抽查加密 HLS 不支持下载；播放未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '光速资源', url: 'https://api.guangsuapi.com/api.php/provide/vod'),
    '本机搜索/详情/分类/首页通过；一份清单超时，另一份通过；抽查加密 HLS 不支持下载；播放未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '如意资源', url: 'https://cj.rycjapi.com/api.php/provide/vod'),
    '本机搜索/详情/分类/首页/清单通过；近期无加密样本首分片 GET 206，HEAD 404；播放/完整下载未验收',
    introducedIn: 2,
  ),
  SourcePreset(
    SourceEndpoint(
        name: '红牛资源', url: 'https://www.hongniuzy2.com/api.php/provide/vod'),
    '仅本机搜索/详情/分类/首页通过；多份媒体清单 TLS 失败，不能确认可播放；请换源',
    introducedIn: 2,
  ),
];

SourcePreset? presetFor(SourceEndpoint source) {
  for (final preset in sourcePresets) {
    if (preset.source.url == source.url) return preset;
  }
  return null;
}
