import '../domain/catalog_item.dart';
import '../domain/vod_provider.dart';
import 'mac_cms_html_parser.dart';
import 'website_transport.dart';

final class MacCmsHtmlProvider implements VodProvider {
  const MacCmsHtmlProvider(this.transport);
  final WebsiteTransport transport;
  MacCmsHtmlParser get parser =>
      MacCmsHtmlParser(transport.source.id, transport.source.endpoint);

  @override
  Future<CatalogPage> search(String query, {int page = 1}) async {
    final uri = transport
        .url('/vodsearch/-------------.html')
        .replace(queryParameters: {'wd': query, 'page': '$page'});
    return parser.listing((await transport.get(uri)).text, page: page);
  }

  @override
  Future<CatalogBrowse> browse({String category = '', int page = 1}) async {
    if (category.isNotEmpty && !RegExp(r'^[0-9]+$').hasMatch(category)) {
      throw const FormatException('分类无效');
    }
    final uri = transport.url(
      category.isEmpty
          ? '/index/home.html'
          : '/vodshow/$category--------$page---.html',
    );
    final result = parser.listing((await transport.get(uri)).text, page: page);
    return CatalogBrowse(
      result,
      categories: const {
        '1': '电影',
        '2': '电视剧',
        '3': '综艺记录',
        '4': '动漫',
        '126': '短剧',
      },
    );
  }

  @override
  Future<CatalogItem> detail(String remoteId) async {
    if (!RegExp(r'^[0-9]+$').hasMatch(remoteId)) {
      throw const FormatException('影片编号无效');
    }
    return parser.detail(
      (await transport.get(transport.url('/voddetail/$remoteId.html'))).text,
      remoteId,
    );
  }

  @override
  Future<ResolvedMedia> resolve(Episode episode) async {
    transport.requireSameOrigin(episode.uri);
    if (!RegExp(
      r'^/vodplay/[0-9]+-[0-9]+-[0-9]+[.]html$',
    ).hasMatch(episode.uri.path)) {
      throw const FormatException('不是支持的播放页');
    }
    final doc = await transport.get(episode.uri);
    return ResolvedMedia(
      parseMacCmsPlayer(doc.text, doc.uri),
      headers: {'Referer': episode.uri.toString(), 'User-Agent': 'Mozilla/5.0'},
    );
  }
}
