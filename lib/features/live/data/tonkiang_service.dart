import 'package:html/parser.dart' as html;
import '../../../core/network/cancellation_token.dart';
import '../../../core/network/document_client.dart';
import '../../sources/domain/video_source.dart';
import '../domain/live_channel.dart';

final class TonkiangResults {
  const TonkiangResults(this.channels, this.nextPage);
  final List<LiveChannel> channels;
  final Uri? nextPage;
}

final class TonkiangService {
  const TonkiangService(this.network);
  final DocumentClient network;
  static final origin = Uri.parse('https://tonkiang.us/');
  static Uri searchUrl(String keyword) =>
      origin.replace(queryParameters: {'keyword': keyword.trim()});

  Future<TonkiangResults> search(
    String keyword, {
    Uri? page,
    CancellationToken? cancellation,
  }) async {
    if (keyword.trim().isEmpty) throw const FormatException('请输入频道名称');
    final uri = page ?? searchUrl(keyword);
    if (uri.host != origin.host ||
        !{'https', 'http'}.contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('搜索分页地址无效');
    }
    try {
      final doc = await network.get(
        uri,
        cancellation: cancellation,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/130.0.0.0 Safari/537.36',
        },
      );
      return parse(doc.text, doc.uri);
    } on RemoteFailure catch (failure) {
      if (failure.kind == FailureKind.cancelled ||
          failure.kind == FailureKind.unsupported) {
        rethrow;
      }
      throw RemoteFailure(
        failure.kind,
        'Tonkiang 访问失败：${failure.message}。可重试，或复制原站搜索链接，在浏览器搜索后粘贴结果文字 / HTML 导入。',
        status: failure.status,
      );
    }
  }

  static TonkiangResults parse(String input, Uri page) {
    final doc = html.parse(input);
    if (page.path.contains('verify') ||
        doc.querySelector('.g-recaptcha, #challenge-form') != null ||
        doc.body?.text.contains('Not a Robot?') == true) {
      throw const RemoteFailure(
        FailureKind.unsupported,
        'Tonkiang 要求人机验证。请在原站搜索后，复制结果文字或保存 HTML，在“粘贴 / 文件导入”中导入。',
      );
    }
    final channels = <String, LiveChannel>{};
    for (final row in doc.querySelectorAll('.resultplus, .result')) {
      final name =
          row.querySelector('.channel .tip, .channel')?.text.trim() ?? '';
      final address = row.querySelector('.mjxj')?.text.trim() ?? '';
      final uri = Uri.tryParse(address);
      if (name.isEmpty ||
          uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        continue;
      }
      final id = stableId('$name|$uri');
      channels[id] = LiveChannel(
        id: id,
        listId: '',
        name: name,
        group: 'Tonkiang',
        urls: [uri],
      );
    }
    Uri? next;
    for (final a in doc.querySelectorAll('a[href]')) {
      if (!{'>>', '下一页', 'Next'}.contains(a.text.trim())) continue;
      final uri = page.resolve(a.attributes['href']!);
      if (uri.host == origin.host && {'http', 'https'}.contains(uri.scheme)) {
        next = uri;
      }
    }
    if (channels.isEmpty && !doc.body!.text.contains('0 results')) {
      throw const FormatException('未识别到搜索结果，可能需要验证或网站结构已变化');
    }
    return TonkiangResults(channels.values.take(200).toList(), next);
  }

  static List<LiveChannel> parseCopiedText(String text, String fallbackName) {
    if (text.contains('<') && text.contains('result')) {
      return parse(text, origin).channels;
    }
    final channels = <LiveChannel>[];
    var name = fallbackName;
    for (final raw in text.split(String.fromCharCode(10))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final uri = Uri.tryParse(line);
      if (uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty) {
        channels.add(
          LiveChannel(
            id: stableId('$name|$uri'),
            listId: '',
            name: name.isEmpty ? uri.host : name,
            group: 'Tonkiang',
            urls: [uri],
          ),
        );
      } else if (!line.contains('checked') && line.length < 100) {
        name = line;
      }
      if (channels.length > 200) {
        throw const FormatException('单次最多导入 200 条搜索结果');
      }
    }
    if (channels.isEmpty) throw const FormatException('未找到 HTTP(S) 频道地址');
    return channels;
  }
}
