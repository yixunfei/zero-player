import 'dart:convert';
import 'dart:io';

import 'package:zero_player/features/books/data/book_import.dart';
import 'package:zero_player/features/books/data/legado/legado_rule_tokens.dart';
import 'package:zero_player/features/books/domain/book.dart';
import 'package:zero_player/features/supervision/domain/adult_source_evidence.dart';
import 'package:zero_player/features/supervision/domain/content_classification.dart';

import 'audit_yckceo.dart' as audit;

Future<void> main(List<String> args) async {
  if (args.length < 2 ||
      args.length > 3 ||
      (args.length == 3 && args[2] != '--inventory-only')) {
    stderr.writeln(
      'Usage: dart run tool/audit_yckceo_legado.dart SNAPSHOT OUTPUT [--inventory-only]',
    );
    exitCode = 64;
    return;
  }
  final builtins =
      jsonDecode(File('assets/catalogs/books/verified.json').readAsStringSync())
          as List;
  final inventory = _Inventory(
    builtins.cast<Map>().map((row) => BookSource.fromJson(row).id).toSet(),
  );
  final files =
      Directory('${args[0]}/details')
          .listSync()
          .whereType<File>()
          .where((file) => _entryName.hasMatch(file.uri.pathSegments.last))
          .toList()
        ..sort((a, b) => _entryId(b).compareTo(_entryId(a)));
  for (final file in files) {
    inventory.read(jsonDecode(file.readAsStringSync()) as Map);
  }
  final output = Directory(args[1])..createSync(recursive: true);
  audit.writeJson(output, 'compatibility.json', inventory.report);
  stdout.writeln(inventory.report);
  if (args.length == 3) return;
  await audit.probeGroups(inventory.candidates, output);
  await stdout.flush();
  exit(0);
}

final _entryName = RegExp(r'^(?:shuyuan|rss)-(\d+)\.json$');

int _entryId(File file) =>
    int.parse(_entryName.firstMatch(file.uri.pathSegments.last)![1]!);

final _restricted = RegExp(
  r'成人|🔞|PO18|BL书|新御书|御书屋|福利|裸|性爱|淫|腐文|高辣|辣肉|肉文|海棠|刘皇叔|黄文|小说搜书地址|\.xyz$',
  caseSensitive: false,
);

final class _Inventory {
  _Inventory(this.builtins);

  final Set<String> builtins;
  final candidates = <String, List<audit.Candidate>>{};
  final _identities = <String>{};
  final _issues = <String, int>{};
  var _rows = 0, _parsed = 0, _v2 = 0, _http = 0, _scripts = 0;

  Map<String, Object> get report => {
    'rows': _rows,
    'parsed': _parsed,
    'unique': _identities.length,
    'v2': _v2,
    'upgradedHttp': _http,
    'script': _scripts,
    'probe': candidates.length,
    'rejected': _issues,
  };

  void read(Map entry) {
    for (final raw in (entry['records'] as List? ?? []).whereType<Map>()) {
      _rows++;
      try {
        final source = parseBookSourceRecord(raw);
        _parsed++;
        _identities.add(source.id);
        if (raw['ruleSearchUrl'] != null) _v2++;
        final address = raw['bookSourceUrl'] ?? raw['sourceUrl'];
        if (address is String && address.startsWith('http://')) _http++;
        _candidate(source, entry['page'] as String);
      } on FormatException catch (error) {
        _issues.update(error.message, (n) => n + 1, ifAbsent: () => 1);
      } on Object {
        _issues.update('记录格式无效', (n) => n + 1, ifAbsent: () => 1);
      }
    }
  }

  void _candidate(BookSource source, String page) {
    final spec = source.legado;
    if (spec == null) return;
    if ([
      spec.search,
      ...spec.explore,
      ...spec.rules.values,
    ].any(legadoScriptMarker.hasMatch)) {
      _scripts++;
    }
    if (builtins.contains(source.id) ||
        knownAdultHost(source.endpoint.host) ||
        _restricted.hasMatch(
          '${source.name} ${source.group} ${source.endpoint.host}',
        ) ||
        adultContent(source.name) ||
        adultContent(source.group, category: true)) {
      return;
    }
    const primaryRules = {
      'searchList',
      'searchTitle',
      'searchLink',
      'exploreList',
      'exploreTitle',
      'exploreLink',
      'toc',
      'chapters',
      'chapterTitle',
      'chapterUrl',
      'content',
      'nextContent',
      'nextToc',
      'articles',
      'articleTitle',
      'articleLink',
    };
    if (legadoScriptMarker.hasMatch(spec.search) ||
        spec.rules.entries.any(
          (rule) =>
              primaryRules.contains(rule.key) &&
              legadoScriptMarker.hasMatch(rule.value),
        )) {
      return;
    }
    if (candidates.length >= 250 && !candidates.containsKey(source.id)) return;
    final variants = candidates.putIfAbsent(source.id, () => []);
    if (variants.length < 2) variants.add((source: source, page: page));
  }
}
