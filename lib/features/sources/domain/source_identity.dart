/// CMS XML/JSON representations identify the same endpoint. Keep query values,
/// custom paths, hosts, schemes and provider kinds distinct.
String sourceIdentity(String kind, Uri endpoint) {
  var path = endpoint.path;
  final query = <String, List<String>>{
    for (final key in endpoint.queryParametersAll.keys.toList()..sort())
      if (!(kind == 'cms' &&
          key == 'at' &&
          {'xml', 'json'}.contains(endpoint.queryParameters[key])))
        key: endpoint.queryParametersAll[key]!,
  };
  if (kind == 'cms') {
    path = path.replaceAll(RegExp(r'/at/(?:xml|json)(?=/|$)'), '');
  }
  path = path.replaceFirst(RegExp(r'/+$'), '');
  return '$kind|${endpoint.replace(path: path.isEmpty ? '/' : path, queryParameters: query.isEmpty ? null : query, query: query.isEmpty ? '' : null, fragment: '')}';
}
