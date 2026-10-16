import 'package:flutter_test/flutter_test.dart';
import 'package:youying/artwork.dart';
import 'package:youying/catalog.dart';
import 'package:youying/library.dart';

class _Catalog extends CatalogClient {
  final requests = <String>[];
  final Map<String, List<MediaEntry>> data = {};

  @override
  Future<List<MediaEntry>> search(SourceEndpoint source, String query) async {
    requests.add('${source.name}:$query');
    return data[source.name] ?? [];
  }
}

void main() {
  const original = MediaEntry(
      id: 'A:1',
      title: '当妈不容易',
      source: 'A',
      year: '2026',
      category: '国产剧',
      actors: '斯琴高娃 , 傅程鹏 , 程愫 , 刘金山',
      poster: 'https://example.com/blocked.webp',
      lines: {
        '正片': [Episode(name: '1', url: 'https://a.example/1.mp4')]
      });
  const replacement = MediaEntry(
      id: 'B:9',
      title: '当妈不容易',
      source: 'B',
      year: '2014',
      category: '国产剧',
      actors: '斯琴高娃,傅程鹏,程愫,刘金山',
      poster: 'https://b.example/working.jpg');

  test('cross-year artwork needs corroborating cast and genre', () {
    expect(matchingArtwork(original, replacement), true);
    expect(
        matchingArtwork(
            original,
            const MediaEntry(
                id: 'B:2',
                title: '当妈不容易',
                source: 'B',
                year: '2014',
                category: '国产剧',
                poster: 'https://b.example/wrong.jpg')),
        false);
    expect(
        matchingArtwork(
            original,
            const MediaEntry(
                id: 'B:3',
                title: '当妈不容易',
                source: 'B',
                year: '2026',
                category: '电影',
                poster: 'https://b.example/wrong.jpg')),
        false);
    expect(
        matchingArtwork(
            original,
            const MediaEntry(
                id: 'B:4',
                title: '当妈不容易',
                source: 'B',
                year: '2026',
                category: '国产剧',
                actors: '陌生演员,另一个演员',
                poster: 'https://b.example/wrong.jpg')),
        false);
  });

  test(
      'failed artwork looks up a matching enabled source once, without changing work',
      () async {
    final client = _Catalog()
      ..data['B'] = [
        const MediaEntry(
            id: 'B:8',
            title: '当妈不容易',
            source: 'B',
            year: '2026',
            category: '电影',
            poster: 'https://b.example/wrong.jpg'),
        replacement,
      ];
    addTearDown(client.dispose);
    final sources = [
      const SourceEndpoint(name: 'A', url: 'https://a.example/api'),
      const SourceEndpoint(name: 'B', url: 'https://b.example/api'),
      const SourceEndpoint(
          name: 'C', url: 'https://c.example/api', enabled: false),
    ];
    final resolver = ArtworkResolver(client, () => sources);
    addTearDown(resolver.dispose);
    final images =
        await Future.wait([resolver.find(original), resolver.find(original)]);
    expect(images, [
      ['https://b.example/working.jpg'],
      ['https://b.example/working.jpg'],
    ]);
    expect(client.requests, ['B:当妈不容易']);
    expect((await resolver.find(original)).single, replacement.poster);
    expect(client.requests, hasLength(1));
    expect(original.poster, 'https://example.com/blocked.webp');
    expect(original.lines['正片']!.single.url, 'https://a.example/1.mp4');
    sources.removeAt(1);
    expect(await resolver.find(original), isEmpty);
  });
}
