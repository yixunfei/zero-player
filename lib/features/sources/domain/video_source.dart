import 'dart:convert';
import 'package:crypto/crypto.dart';

String stableId(String value) => sha256.convert(utf8.encode(value)).toString();

final class VideoSource {
  const VideoSource({
    required this.id,
    required this.name,
    required this.endpoint,
    this.enabled = false,
    this.headers = const {},
    this.classification = 'unknown',
    this.failures = 0,
    this.retryAfter,
    this.apiOk = false,
    this.error,
    this.siteTitle,
    this.homepage,
    this.latencyMs,
    this.checkedAt,
    this.suppressed = false,
    this.kind = 'cms',
  });
  final String id;
  final String kind;
  final String name;
  final Uri endpoint;
  final bool enabled;
  final Map<String, String> headers;
  final String classification;
  final int failures;
  final DateTime? retryAfter;
  final bool apiOk;
  final String? error;
  final String? siteTitle;
  final Uri? homepage;
  final int? latencyMs;
  final DateTime? checkedAt;
  final bool suppressed;
  String get displayName =>
      siteTitle?.trim().isNotEmpty == true && name == endpoint.host
      ? siteTitle!
      : name;
  String get description => [
    if (siteTitle != null && siteTitle != displayName) siteTitle!,
    homepage?.host ?? endpoint.host,
    if (latencyMs != null) '$latencyMs ms',
  ].join(' · ');
  bool get available =>
      enabled &&
      !suppressed &&
      (retryAfter == null || retryAfter!.isBefore(DateTime.now()));

  factory VideoSource.fromRow(Map<String, Object?> row) => VideoSource(
    id: row['id'] as String,
    kind: row['kind'] as String? ?? 'cms',
    name: row['display_name'] as String? ?? row['name'] as String,
    endpoint: Uri.parse(row['endpoint'] as String),
    enabled: row['enabled'] == 1,
    headers: Map<String, String>.from(jsonDecode(row['headers'] as String)),
    classification: row['classification'] as String,
    failures: row['failures'] as int? ?? 0,
    apiOk: row['api_ok'] == 1,
    error: row['last_error'] as String?,
    siteTitle: row['site_title'] as String?,
    homepage: row['homepage'] == null
        ? null
        : Uri.tryParse(row['homepage'] as String),
    latencyMs: row['latency_ms'] as int?,
    suppressed: row['suppressed'] == 1,
    checkedAt: row['checked_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['checked_at'] as int),
    retryAfter: row['retry_after'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['retry_after'] as int),
  );
}
