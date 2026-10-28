enum SourceKind { cms, livePlaylist, kanju, macCmsHtml }

final class SourceCandidate {
  const SourceCandidate({
    required this.name,
    required this.endpoint,
    required this.kind,
    required this.requestedEnabled,
    this.classification = 'unknown',
  });
  final String name;
  final Uri endpoint;
  final SourceKind kind;
  final String classification;

  /// Imported preference only. Parsing never proves API/media availability.
  final bool requestedEnabled;
}

final class CatalogReference {
  const CatalogReference(this.name, this.uri);
  final String name;
  final Uri uri;
}

final class ImportDiagnostic {
  const ImportDiagnostic(this.name, this.reason);
  final String name;
  final String reason;
}

final class SourceCatalog {
  SourceCatalog({
    required List<SourceCandidate> sources,
    required List<CatalogReference> references,
    required List<ImportDiagnostic> diagnostics,
    List<LiveCatalogEntry> lives = const [],
  }) : sources = List.unmodifiable(sources),
       references = List.unmodifiable(references),
       diagnostics = List.unmodifiable(diagnostics),
       lives = List.unmodifiable(lives);
  final List<LiveCatalogEntry> lives;
  final List<SourceCandidate> sources;
  final List<CatalogReference> references;
  final List<ImportDiagnostic> diagnostics;
}

final class LiveCatalogEntry {
  const LiveCatalogEntry(
    this.name,
    this.url, {
    this.epg,
    this.headers = const {},
  });
  final String name;
  final Uri url;
  final Uri? epg;
  final Map<String, String> headers;
}

abstract interface class SourceCatalogParser {
  SourceCatalog parse(String input, Uri origin);
}
