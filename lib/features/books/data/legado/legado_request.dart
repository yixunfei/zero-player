import 'dart:convert';

import 'package:enough_convert/gbk.dart';

import '../../../../core/network/document_encoding.dart';
import '../../../sources/data/jsonc_decoder.dart';
import '../../domain/book.dart';

final _optionsStart = RegExp(r',\s*\{');
final _placeholders = RegExp(r'\{\{(.*?)\}\}', dotAll: true);

String legadoAddressPart(String rule) {
  final index = rule.indexOf(_optionsStart);
  return (index == -1 ? rule : rule.substring(0, index)).trim();
}

Object? decodeLegadoJson(String input) {
  try {
    return jsonDecode(input);
  } on FormatException {
    // Android's JSON reader also accepts quoted strings and unquoted keys.
    final tokens = RegExp(
      r"""'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|[A-Za-z_][\w-]*(?=\s*:)""",
    );
    final normalized = input.replaceAllMapped(tokens, (match) {
      final value = match[0]!;
      if (value.startsWith('"')) return value;
      if (!value.startsWith("'")) return jsonEncode(value);
      return jsonEncode(
        value.substring(1, value.length - 1).replaceAll(r"\'", "'"),
      );
    });
    return decodeJsonc(normalized);
  }
}

Map<String, String> legadoHeaders(Object? raw, Uri base) {
  if (raw is String) {
    try {
      raw = decodeLegadoJson(raw);
    } on FormatException {
      return const {};
    }
  }
  if (raw is! Map) return const {};
  const names = {
    'user-agent': 'User-Agent',
    'accept': 'Accept',
    'accept-language': 'Accept-Language',
    'referer': 'Referer',
    'origin': 'Origin',
  };
  final headers = <String, String>{};
  for (final entry in raw.entries) {
    final name = names['${entry.key}'.toLowerCase()];
    final value = entry.value;
    if (name == null ||
        value is! String ||
        value.isEmpty ||
        value.length > 1024 ||
        RegExp(
          r'[\x00-\x1f\x7f]|\{\{|@js:|<js>',
          caseSensitive: false,
        ).hasMatch(value)) {
      continue;
    }
    if (name == 'Referer' || name == 'Origin') {
      try {
        final referer = legacyBookUri(Uri.parse(value));
        if (referer.host != base.host) continue;
        headers[name] = name == 'Origin'
            ? referer.origin
            : Uri(
                scheme: 'https',
                host: referer.host,
                path: referer.path,
              ).toString();
      } on FormatException {
        continue;
      }
    } else {
      headers[name] = value;
    }
  }
  return headers;
}

final class LegadoRequest {
  LegadoRequest._(
    this.uri,
    this.headers,
    this._specificHeaders,
    this.encoding,
    this.form,
    this.json,
  );

  factory LegadoRequest.parse(
    BookSource source,
    Uri base,
    String rule, {
    String key = '',
    int page = 1,
    bool media = false,
  }) {
    final start = rule.indexOf(_optionsStart);
    final options = start == -1
        ? const {}
        : decodeLegadoJson(rule.substring(start + 1));
    if (options is! Map) throw const FormatException('Legado URL 请求选项无效');
    final charset = '${options['charset'] ?? 'utf-8'}'.toLowerCase().replaceAll(
      '_',
      '-',
    );
    final encoding = switch (charset) {
      'utf-8' || 'utf8' => utf8,
      'gbk' || 'gb2312' || 'gb-2312' || 'gb18030' || 'cp936' => gbk,
      'ascii' => ascii,
      'latin1' || 'iso-8859-1' => latin1,
      _ => throw const FormatException('搜索 URL 使用不支持的字符集'),
    };
    final String method = '${options['method'] ?? 'GET'}'.toUpperCase();
    final address = _render(
      legadoAddressPart(rule),
      key: encodeDocumentComponent(key, encoding),
      page: page,
      base: base,
    );
    final uri = source.resolve(base, address, media: media);
    final specificHeaders = legadoHeaders(
      options['headers'] ?? options['header'],
      source.endpoint,
    );
    final headers = {
      ...legadoHeaders(source.legado?.headers, source.endpoint),
      ...specificHeaders,
    };
    if (method == 'GET') {
      return LegadoRequest._(
        uri,
        headers,
        specificHeaders,
        encoding,
        null,
        null,
      );
    }
    if (method != 'POST') throw const FormatException('Legado 仅支持 GET 和 POST');
    final body = options['body'];
    final object = body is String && body.trimLeft().startsWith('{')
        ? decodeLegadoJson(body)
        : body;
    if (object is Map) {
      final rendered =
          _renderJson(object, key, page, base, 0) as Map<String, Object?>;
      return LegadoRequest._(
        uri,
        headers,
        specificHeaders,
        encoding,
        null,
        rendered,
      );
    }
    if (body is! String && body != null) {
      throw const FormatException('Legado POST 请求体无效');
    }
    final fields = Uri.splitQueryString(
      body as String? ?? '',
      encoding: encoding,
    );
    if (fields.length > 40) throw const FormatException('Legado 表单字段过多');
    final form = {
      for (final entry in fields.entries)
        entry.key: _render(entry.value, key: key, page: page, base: base),
    };
    return LegadoRequest._(uri, headers, specificHeaders, encoding, form, null);
  }

  final Uri uri;
  final Map<String, String> headers;
  final Map<String, String> _specificHeaders;
  final Encoding encoding;
  final Map<String, String>? form;
  final Map<String, Object?>? json;

  late final String reference = _reference();

  String get targetKey => reference.isEmpty ? '$uri' : reference;

  String _reference() {
    if (_specificHeaders.isEmpty && form == null && json == null) return '';
    final data = form;
    final body = data == null ? json : encodeDocumentForm(data, encoding);
    return '$uri,${jsonEncode({if (_specificHeaders.isNotEmpty) 'headers': _specificHeaders, if (body != null) 'method': 'POST', 'body': ?body, if (data != null && encoding != utf8) 'charset': encoding.name})}';
  }
}

Object? _renderJson(Object? data, String key, int page, Uri base, int depth) {
  if (depth > 12) throw const FormatException('Legado 请求体嵌套过深');
  return switch (data) {
    String value => _render(value, key: key, page: page, base: base),
    Map value => <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _renderJson(
          entry.value,
          key,
          page,
          base,
          depth + 1,
        ),
    },
    List value =>
      value
          .map((item) => _renderJson(item, key, page, base, depth + 1))
          .toList(),
    _ => data,
  };
}

String _render(
  String input, {
  required String key,
  required int page,
  required Uri base,
}) {
  final paging = input.replaceAllMapped(RegExp(r'<([^<>]*)>'), (match) {
    final choices = match[1]!.split(',');
    return choices[(page - 1).clamp(0, choices.length - 1)].trim();
  });
  return paging.replaceAllMapped(_placeholders, (match) {
    final expression = match[1]!.replaceAll(RegExp(r'\s+'), '');
    if (const {
      'key',
      'encodeURIComponent(key)',
      'java.encodeURI(key)',
    }.contains(expression)) {
      return key;
    }
    if (expression == 'baseUrl') return '$base';
    final arithmetic = RegExp(
      r'^\(?page(?:([+-])(\d+))?\)?(?:\*(\d+))?$',
    ).firstMatch(expression);
    if (arithmetic == null) {
      throw const FormatException('Legado URL 使用未支持的模板表达式');
    }
    final offset = int.tryParse(arithmetic[2] ?? '') ?? 0;
    final factor = int.tryParse(arithmetic[3] ?? '') ?? 1;
    return '${(page + (arithmetic[1] == '-' ? -offset : offset)) * factor}';
  });
}
