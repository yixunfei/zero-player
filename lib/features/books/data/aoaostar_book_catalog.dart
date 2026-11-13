import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'book_import.dart';

const _assetPath = 'assets/catalogs/books/legado';

typedef AoaoStarBookPack = ({String id, String name, int count});

final class AoaoStarBookCatalog {
  const AoaoStarBookCatalog(this.packs, this._archiveDigest);

  final List<AoaoStarBookPack> packs;
  final String _archiveDigest;
  String get revision => _archiveDigest;

  static Future<AoaoStarBookCatalog> load() async {
    final manifest =
        jsonDecode(await rootBundle.loadString('$_assetPath/manifest.json'))
            as Map;
    return AoaoStarBookCatalog([
      for (final pack in (manifest['packs'] as List).cast<Map>())
        (
          id: pack['id'] as String,
          name: pack['name'] as String,
          count: pack['count'] as int,
        ),
    ], manifest['archiveSha256'] as String);
  }

  Future<BookSourceImport> read({String? packId}) async {
    final selected = packs.where((pack) => packId == null || pack.id == packId);
    final counts = {for (final pack in selected) pack.id: pack.count};
    if (counts.isEmpty) throw const FormatException('找不到该书源包');
    final data = await rootBundle.load('$_assetPath/catalog.json.bz2');
    final archive = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final digest = _archiveDigest;
    return Isolate.run(() => _decodeCatalog(archive, digest, counts));
  }
}

BookSourceImport _decodeCatalog(
  Uint8List archive,
  String digest,
  Map<String, int> counts,
) {
  if (sha256.convert(archive).toString() != digest) {
    throw const FormatException('内置书源包校验失败');
  }
  final data =
      jsonDecode(utf8.decode(BZip2Decoder().decodeBytes(archive))) as Map;
  final records = data['records'] as List;
  final packs = data['packs'] as Map;
  return parseBookSourceRecords(_packRecords(counts, packs, records));
}

Iterable<Object?> _packRecords(
  Map<String, int> counts,
  Map packs,
  List records,
) sync* {
  for (final MapEntry(key: id, value: count) in counts.entries) {
    final references = packs[id] as List;
    if (references.length != count) throw const FormatException('内置书源包条目数不一致');
    for (final index in references.cast<int>()) {
      yield records[index];
    }
  }
}
