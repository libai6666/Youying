import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'catalog.dart';

class HlsAsset {
  const HlsAsset(this.uri, this.name);
  final Uri uri;
  final String name;
}

/// A deliberately limited, unencrypted VOD subset. No key or licence requests.
class HlsPlan {
  HlsPlan({this.variant, this.manifest = '', this.assets = const []});
  final Uri? variant;
  final String manifest;
  final List<HlsAsset> assets;

  static Map<String, String> _attributes(String input) {
    final result = <String, String>{};
    final pattern = RegExp(r'([A-Z0-9-]+)=("[^"\r\n]*"|[^,\s]+)(?:,|$)');
    var offset = 0;
    for (final match in pattern.allMatches(input)) {
      if (match.start != offset || result.containsKey(match[1])) {
        throw const FormatException('HLS 属性格式无效');
      }
      final value = match[2]!;
      result[match[1]!] =
          value.startsWith('"') ? value.substring(1, value.length - 1) : value;
      offset = match.end;
    }
    if (offset != input.length) throw const FormatException('HLS 属性格式无效');
    return result;
  }

  static HlsPlan parse(String text, Uri base) {
    final lines = const LineSplitter().convert(text.trim());
    if (lines.isEmpty || lines.first != '#EXTM3U') {
      throw const FormatException('不是有效的 M3U8 清单');
    }
    Uri resolve(String value) =>
        SourceEndpoint.parseHttps(base.resolve(value).toString());
    final master = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF:'));
    if (master) {
      Uri? variant;
      var expectsUri = false;
      for (final raw in lines.skip(1)) {
        final line = raw.trim();
        if (line.isEmpty) continue;
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          if (expectsUri) throw const FormatException('HLS 线路地址缺失');
          final attributes = _attributes(line.substring(line.indexOf(':') + 1));
          if (attributes.containsKey('AUDIO') ||
              attributes.containsKey('VIDEO') ||
              attributes.containsKey('SUBTITLES')) {
            throw const FormatException('暂不支持分离音轨或字幕的 HLS 下载');
          }
          expectsUri = true;
        } else if (!line.startsWith('#')) {
          if (!expectsUri) throw const FormatException('HLS 线路格式无效');
          final uri = resolve(line);
          variant ??= uri;
          expectsUri = false;
        } else if (line.startsWith('#EXT') &&
            !line.startsWith('#EXT-X-VERSION:') &&
            line != '#EXT-X-INDEPENDENT-SEGMENTS') {
          throw const FormatException('暂不支持该 HLS 主清单标签');
        }
      }
      if (expectsUri || variant == null) {
        throw const FormatException('HLS 没有可下载的线路');
      }
      return HlsPlan(variant: variant);
    }

    if (!lines.any((line) => line.trim() == '#EXT-X-ENDLIST')) {
      throw const FormatException('只支持已结束的 HLS 点播，不支持直播');
    }
    final assets = <HlsAsset>[];
    final output = <String>['#EXTM3U'];
    var expectsSegment = false;
    var segments = 0;
    var ended = false;
    var targetDuration = false;
    String addAsset(String value) {
      if (assets.length >= 5000) throw const FormatException('HLS 分片超过 5000 个');
      final uri = resolve(value);
      final match = RegExp(r'\.(ts|m4s|mp4|aac|vtt)$', caseSensitive: false)
          .firstMatch(uri.path);
      final extension = match?.group(1)?.toLowerCase() ?? 'bin';
      final name = 'asset${assets.length}.$extension';
      assets.add(HlsAsset(uri, name));
      return name;
    }

    for (final raw in lines.skip(1)) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (!line.startsWith('#')) {
        if (!expectsSegment || ended) throw const FormatException('HLS 分片顺序无效');
        output.add(addAsset(line));
        segments++;
        expectsSegment = false;
      } else if (line.startsWith('#EXTINF:')) {
        final duration = double.tryParse(line.substring(8).split(',').first);
        if (expectsSegment ||
            ended ||
            duration == null ||
            !duration.isFinite ||
            duration <= 0) {
          throw const FormatException('HLS 分片时长无效');
        }
        expectsSegment = true;
        output.add('#EXTINF:$duration,');
      } else if (line.startsWith('#EXT-X-MAP:')) {
        final attributes = _attributes(line.substring(11));
        if (attributes.length != 1 || !attributes.containsKey('URI') || ended) {
          throw const FormatException('暂不支持 HLS 字节范围初始化分片');
        }
        output.add('#EXT-X-MAP:URI="${addAsset(attributes['URI']!)}"');
      } else if (line.startsWith('#EXT-X-KEY:')) {
        final attributes = _attributes(line.substring(11));
        if (attributes.length != 1 || attributes['METHOD'] != 'NONE') {
          throw const FormatException('不支持加密 HLS 或 DRM 下载');
        }
      } else if (line == '#EXT-X-ENDLIST') {
        if (expectsSegment || ended) throw const FormatException('HLS 结束标记无效');
        ended = true;
        output.add(line);
      } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
        final duration = int.tryParse(line.split(':').last);
        if (duration == null || duration <= 0) {
          throw const FormatException('HLS 目标时长无效');
        }
        targetDuration = true;
        output.add(line);
      } else if (line.startsWith('#EXT-X-VERSION:') ||
          line.startsWith('#EXT-X-MEDIA-SEQUENCE:') ||
          line.startsWith('#EXT-X-DISCONTINUITY-SEQUENCE:')) {
        final value = int.tryParse(line.split(':').last);
        if (value == null || value < 0) throw const FormatException('HLS 数值无效');
        output.add(line);
      } else if (const {
        '#EXT-X-INDEPENDENT-SEGMENTS',
        '#EXT-X-DISCONTINUITY',
        '#EXT-X-PLAYLIST-TYPE:VOD',
        '#EXT-X-PLAYLIST-TYPE:EVENT'
      }.contains(line)) {
        output.add(line);
      } else if (line.startsWith('#EXT-X-PROGRAM-DATE-TIME:')) {
        // Timestamps are unnecessary for this local VOD playlist.
      } else if (line.startsWith('#EXT')) {
        throw const FormatException('暂不支持该 HLS 标签（如字节范围、分离音轨或直播分片）');
      }
    }
    if (segments == 0 || expectsSegment || !targetDuration) {
      throw const FormatException('HLS 没有完整的点播分片');
    }
    return HlsPlan(manifest: '${output.join('\n')}\n', assets: assets);
  }
}

class MediaDownloader {
  MediaDownloader({http.Client? client, this.maxBytes = 2 * 1024 * 1024 * 1024})
      : _client = client ?? http.Client();
  final http.Client _client;
  final int maxBytes;
  bool _running = false;

  Future<String> download(
    String address,
    Directory destination, {
    Map<String, String> headers = const {},
    void Function(int received, int? total)? onProgress,
  }) async {
    if (_running) throw StateError('Download already running');
    final origin = SourceEndpoint.parseHttps(address);
    parseHeaders(jsonEncode(headers));
    final temporary = Directory('${destination.path}.partial');
    _running = true;
    var received = 0;
    var ownsTemporary = false;
    try {
      if (await destination.exists()) {
        throw const FormatException('下载目录已存在，请勿覆盖');
      }
      if (await temporary.exists()) {
        throw const FormatException('存在未完成下载，请先清理后重试');
      }
      await temporary.create(recursive: true);
      ownsTemporary = true;
      Future<http.StreamedResponse> request(Uri uri) async {
        final request = http.Request('GET', uri)..followRedirects = false;
        // Never forward caller-supplied credentials to a different HLS origin.
        if (uri.origin == origin.origin) request.headers.addAll(headers);
        final response =
            await _client.send(request).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          await response.stream.listen(null).cancel();
          throw HttpException('下载返回 HTTP ${response.statusCode}，不自动跟随重定向');
        }
        return response;
      }

      Future<void> save(Uri uri, String name, {bool direct = false}) async {
        final response = await request(uri);
        final length = response.contentLength;
        if (length != null && (length <= 0 || length > maxBytes - received)) {
          await response.stream.listen(null).cancel();
          throw const FormatException('下载超过大小限制或文件为空');
        }
        var fileBytes = 0;
        final stream =
            response.stream.timeout(const Duration(seconds: 30)).map((chunk) {
          received += chunk.length;
          fileBytes += chunk.length;
          if (received > maxBytes || (length != null && fileBytes > length)) {
            throw const FormatException('下载超过大小限制');
          }
          onProgress?.call(received, direct ? length : null);
          return chunk;
        });
        final sink = File('${temporary.path}/$name').openWrite();
        try {
          await sink.addStream(stream);
          await sink.flush();
        } catch (_) {
          // addStream can already close the file; preserve the stream failure.
          try {
            await sink.close();
          } on FileSystemException {
            // Already closed by the failed stream.
          }
          rethrow;
        }
        await sink.close();
        if (fileBytes == 0 || (length != null && length != fileBytes)) {
          throw const FormatException('下载文件不完整');
        }
      }

      final path = origin.path.toLowerCase();
      String local;
      if (path.endsWith('.m3u8')) {
        var uri = origin;
        final visited = <Uri>{};
        HlsPlan? plan;
        for (var depth = 0; depth < 4; depth++) {
          if (!visited.add(uri)) throw const FormatException('HLS 主清单循环引用');
          final response = await request(uri);
          final bytes = <int>[];
          await for (final chunk
              in response.stream.timeout(const Duration(seconds: 30))) {
            if (bytes.length + chunk.length > 2 * 1024 * 1024) {
              throw const FormatException('HLS 清单超过 2MB');
            }
            bytes.addAll(chunk);
          }
          plan = HlsPlan.parse(utf8.decode(bytes), uri);
          if (plan.variant == null) break;
          uri = plan.variant!;
        }
        if (plan == null || plan.variant != null) {
          throw const FormatException('HLS 嵌套层数过多');
        }
        for (final asset in plan.assets) {
          await save(asset.uri, asset.name);
        }
        local = 'index.m3u8';
        await File('${temporary.path}/$local')
            .writeAsString(plan.manifest, flush: true);
      } else if (path.endsWith('.mp4') || path.endsWith('.webm')) {
        local = path.endsWith('.mp4') ? 'video.mp4' : 'video.webm';
        await save(origin, local, direct: true);
      } else {
        throw const FormatException('只支持 MP4、WebM 和无加密的 M3U8 点播下载');
      }
      await temporary.rename(destination.path);
      return '${destination.path}/$local';
    } finally {
      _running = false;
      if (ownsTemporary && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    }
  }

  void close() => _client.close();
}
