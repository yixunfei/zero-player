import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:zero_player/core/network/cancellation_token.dart';
import 'package:zero_player/core/network/document_client.dart';
import 'package:zero_player/core/network/media_http_client.dart';
import 'package:zero_player/core/network/request_scheduler.dart';
import 'package:zero_player/features/books/data/audiobook_format.dart';
import 'package:zero_player/features/books/data/book_client.dart';
import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/supervision/domain/adult_source_evidence.dart';
import 'package:zero_player/features/supervision/domain/content_classification.dart';

typedef Candidate = ({BookSource source, String page});

final _video = RegExp(r'动漫|动画|短剧|影视|电影|影院|视频|直播|iptv', caseSensitive: false);
final _audio = RegExp(r'听书|有声|播客|广播剧|podcast|librivox', caseSensitive: false);
final _feed = RegExp(
  r'/(?:[^/?#]*\.(?:rss|atom|xml)|(?:rss|atom|feeds?)(?:[/.?]|$))',
  caseSensitive: false,
);
final _restricted = RegExp(
  r'🔞|成人|色情|肉文|肉色|色文|御宅|耽美肉|第一版主|秀人|福利姬|黄书|情色|bl文|h文|情色小说',
  caseSensitive: false,
);

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run tool/audit_yckceo.dart SNAPSHOT OUTPUT');
    exitCode = 64;
    return;
  }
  final output = Directory(args[1])..createSync(recursive: true);
  final (groups, counts, other) = inventory(Directory('${args[0]}/details'));
  writeJson(output, 'inventory.json', {
    'counts': counts,
    'identities': groups.length,
    'candidates': groups.values.expand((value) => value).length,
    'mediaReview': other,
  });
  stdout.writeln('${groups.length} unique book/feed candidates, $counts');
  await probeGroups(groups, output);
  stdout.writeln('Probe report written to ${output.path}/probes.jsonl');
  await stdout.flush();
  // Timed-out system DNS lookups may remain active after sockets are closed.
  exit(0);
}

(Map<String, List<Candidate>>, Map<String, int>, List<Map>) inventory(
  Directory details,
) {
  final groups = <String, List<Candidate>>{};
  final variants = <String>{};
  final counts = <String, int>{};
  final other = <Map>[];
  final seenMedia = <String>{};
  void count(String key) => counts.update(key, (n) => n + 1, ifAbsent: () => 1);
  final files =
      details
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) {
          final section = a.uri.pathSegments.last.split('-').first;
          final otherSection = b.uri.pathSegments.last.split('-').first;
          final comparison = section.compareTo(otherSection);
          return comparison == 0
              ? _entryNumber(b).compareTo(_entryNumber(a))
              : comparison;
        });
  for (final file in files) {
    final entry = jsonDecode(file.readAsStringSync()) as Map;
    if (entry['members'] is List) {
      count('collectionMembersOnly');
      for (final row in entry['members'] as List) {
        _mediaReview(row[0], row[1], null, entry['page'], seenMedia, other);
      }
    }
    for (final row in entry['records'] as List? ?? const []) {
      count('records');
      final raw = row as Map;
      final name = bookLabel(raw['bookSourceName'] ?? raw['sourceName']);
      final url = bookLabel(raw['bookSourceUrl'] ?? raw['sourceUrl'], 2048);
      final group = bookLabel(raw['bookSourceGroup'] ?? raw['sourceGroup']);
      final type = raw['bookSourceType']?.toString();
      final publisher = '$name $url';
      if (adultContent(publisher) ||
          adultContent(group, category: true) ||
          _restricted.hasMatch('$publisher $group') ||
          knownAdultHost(Uri.tryParse(url)?.host ?? '')) {
        count('restricted');
        continue;
      }
      if (_mediaReview(name, url, type, entry['page'], seenMedia, other)) {
        count('otherMedia');
        continue;
      }
      try {
        final source = candidateSource(raw, url, name, group);
        final identity = source.toJson()
          ..remove('name')
          ..remove('group');
        if (!variants.add(jsonEncode(identity))) {
          count('duplicateRules');
          continue;
        }
        final choices = groups.putIfAbsent(source.id, () => []);
        if (choices.length < 5) {
          choices.add((source: source, page: entry['page'] as String));
        }
      } catch (_) {
        count('unsupported');
      }
    }
  }
  return (groups, counts, other);
}

int _entryNumber(File file) =>
    int.parse(file.uri.pathSegments.last.split('-').last.split('.').first);

bool _mediaReview(
  String name,
  String url,
  String? type,
  String page,
  Set<String> seen,
  List<Map> output,
) {
  final isMedia =
      type == '4' ||
      (!_audio.hasMatch(name) && _video.hasMatch(name)) ||
      RegExp(
        r'/api\.php/provide/vod|\.m3u8?(?:[?#]|$)',
        caseSensitive: false,
      ).hasMatch(url);
  if (isMedia && seen.add(url)) {
    output.add({'name': name, 'url': url, 'page': page});
  }
  return isMedia;
}

BookSource candidateSource(Map raw, String url, String name, String group) {
  if (!raw.containsKey('sourceUrl')) return parseBookSourceRecord(raw);
  final audio = _audio.hasMatch('$name $group');
  final secure = Uri.parse(url).replace(scheme: 'https');
  if (!_feed.hasMatch(secure.path) && !audio) {
    throw const FormatException('订阅未声明 RSS 或 Atom 路径');
  }
  return BookSource.fromJson({
    'name': name,
    'url': secure.toString(),
    'kind': audio ? 'audio' : 'text',
    'format': 'feed',
    'group': audio ? '有声订阅' : '文章订阅',
  });
}

Future<void> probeGroups(
  Map<String, List<Candidate>> groups,
  Directory output,
) async {
  const concurrency = 48;
  final scheduler = RequestScheduler(
    globalLimit: concurrency + 2,
    playbackReserve: 2,
  );
  final http = MediaHttpClient(
    timeout: const Duration(seconds: 8),
    maxConnectionsPerHost: 2,
    allowLegacyQueryEncoding: true,
    scheduler: scheduler,
  );
  final client = BookClient(DocumentClient(http));
  final pending = groups.values.iterator;
  final report = File('${output.path}/probes.jsonl');
  final existing = _resumeProbes(report);
  var completed = 0;
  try {
    await Future.wait(
      List.generate(min(groups.length, concurrency), (_) async {
        while (pending.moveNext()) {
          final choices = pending.current;
          final id = choices.first.source.id;
          if (existing.contains(id)) continue;
          final attempts = <Map>[];
          for (final candidate in choices) {
            try {
              final result = await probe(client, candidate);
              attempts.add(result);
              stdout.writeln(
                'PASS ${candidate.source.kind.name} ${candidate.source.name}',
              );
              break;
            } catch (error) {
              attempts.add({
                'page': candidate.page,
                'url': candidate.source.endpoint.toString(),
                'error': error is FormatException
                    ? error.message
                    : error.toString(),
              });
            }
          }
          report.writeAsStringSync(
            '${jsonEncode({'id': id, 'attempts': attempts})}\n',
            mode: FileMode.append,
          );
          if (++completed % 20 == 0) stdout.writeln('probed $completed');
        }
      }),
    );
  } finally {
    http.close();
    scheduler.close();
  }
}

Set<Object?> _resumeProbes(File report) {
  if (!report.existsSync()) return {};
  final lines = report.readAsLinesSync();
  final ids = <Object?>{};
  for (final (index, line) in lines.indexed) {
    try {
      ids.add((jsonDecode(line) as Map)['id']);
    } on FormatException {
      if (index != lines.length - 1) rethrow;
      report.writeAsStringSync('${lines.take(index).join('\n')}\n');
    }
  }
  return ids;
}

Future<Map> probe(BookClient client, Candidate candidate) async {
  final source = candidate.source;
  final token = CancellationToken();
  final timer = Timer(const Duration(seconds: 40), token.cancel);
  try {
    final (book, query, discovered) = await findSample(client, source, token);
    final chapters = await client.chapters(source, book, token);
    for (final chapter in chapters.take(3)) {
      if (_restricted.hasMatch(chapter.title) || adultContent(chapter.title)) {
        continue;
      }
      final Map evidence;
      if (source.kind == BookKind.audio) {
        final (uri, bytes) = await client.sampleAudio(
          source,
          chapter,
          token,
          book: book,
        );
        evidence = {
          'audio': audiobookExtension(bytes, isM4b: uri.path.endsWith('.m4b')),
        };
      } else {
        final body = await client.text(source, chapter, token, book: book);
        if (body.length < 150 || adultContent(body)) continue;
        evidence = {'characters': body.length};
      }
      return {
        'page': candidate.page,
        'source': source.toJson()
          ..['sample'] = query
          ..['originNote'] = candidate.page
          ..['discover'] = discovered ? source.discover : '',
        'work': book.title,
        'chapter': chapter.title,
        'chapters': chapters.length,
        ...evidence,
      };
    }
    throw const FormatException('未取得可用章节或正文');
  } finally {
    timer.cancel();
  }
}

Future<(Book, String, bool)> findSample(
  BookClient client,
  BookSource source,
  CancellationToken token,
) async {
  bool permitted(Book book) =>
      !adultContent('${book.title} ${book.description}') &&
      !_restricted.hasMatch('${book.title} ${book.description}');
  if (source.format == BookFormat.feed) {
    final book = (await client.books(source, '', token)).where(permitted).first;
    return (book, '', true);
  }
  var discovered = <Book>[];
  if (source.hasDiscovery) {
    try {
      discovered = (await client.books(
        source,
        '',
        token,
      )).where(permitted).toList();
    } on Exception {
      token.check();
    }
  }
  for (final query in {
    if (source.sample.isNotEmpty) source.sample,
    ...discovered.take(2).map((book) => book.title),
    '斗破苍穹',
    '三体',
    '诡秘之主',
  }) {
    final results = await client.books(source, query, token);
    final key = bookIdentity(query);
    final exact = results
        .where(permitted)
        .where((book) => bookIdentity(book.title) == key);
    if (exact.isNotEmpty) return (exact.first, query, discovered.isNotEmpty);
  }
  throw const FormatException('未搜到样本作品');
}

void writeJson(Directory output, String name, Object value) => File(
  '${output.path}/$name',
).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(value)}\n');
