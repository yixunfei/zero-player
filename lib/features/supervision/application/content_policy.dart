import 'package:flutter/foundation.dart';
import '../../catalog/domain/catalog_item.dart';
import '../../live/domain/channel_identity.dart';
import '../../live/domain/live_channel.dart';
import '../../settings/application/settings_controller.dart';
import '../../sources/domain/source_identity.dart';
import '../../sources/domain/video_source.dart';
import '../domain/content_classification.dart';
import '../domain/supervision_rules.dart';
import 'supervision_controller.dart';

/// Shared by listing, detail, playback, radio and download boundaries.
final class ContentPolicy extends ChangeNotifier {
  ContentPolicy(this.settings, this.supervision) {
    _adultFilter = settings.value.filterAdult;
    settings.addListener(_settingsChanged);
    supervision.addListener(notifyListeners);
  }
  late bool _adultFilter;
  void _settingsChanged() {
    if (_adultFilter == settings.value.filterAdult) return;
    _adultFilter = settings.value.filterAdult;
    notifyListeners();
  }

  final SettingsController settings;
  final SupervisionController supervision;
  final _sources = <String, VideoSource>{};
  final _live = <String, LiveChannel>{};
  final _programs = <String, List<EpgProgram>>{};
  final _categories = <String, (DateTime, Map<String, String>)>{};
  bool get filterAdult => settings.value.filterAdult;
  bool get active => filterAdult || supervision.enabled;
  String sourceKey(VideoSource source) =>
      'vod:${stableId(sourceIdentity(source.kind, source.endpoint))}';
  String channelKey(String name, {bool radio = false}) =>
      (radio ? 'radio:' : 'live:') + stableId(channelIdentity(name));
  void rememberSource(VideoSource source) {
    final previous = _sources[source.id];
    _sources[source.id] = source;
    if (previous != null &&
        (previous.classification != source.classification ||
            previous.name != source.name ||
            previous.displayName != source.displayName ||
            previous.siteTitle != source.siteTitle ||
            previous.endpoint != source.endpoint)) {
      notifyListeners();
    }
  }

  void forgetSources() => _sources.clear();
  void rememberChannels(Iterable<LiveChannel> channels) {
    _live.clear();
    for (final channel in channels) {
      _live[channel.name] = channel;
    }
  }

  LiveChannel? liveChannel(String name) => _live[name];
  void rememberPrograms(String name, List<EpgProgram> programs) {
    _programs[name] = List.unmodifiable(programs);
  }

  bool _programAllowed(String name) {
    final now = DateTime.now();
    return (_programs[name] ?? const <EpgProgram>[])
        .where((p) => !p.start.isAfter(now) && p.end.isAfter(now))
        .every((p) => textAllowed(p.title));
  }

  bool liveNameAllowed(String name) {
    if (!_programAllowed(name)) return false;
    final channel = _live[name];
    return channel == null
        ? textAllowed(name) &&
              !(supervision.enabled &&
                  supervision.rules.blocksKey(channelKey(name)))
        : channelAllowed(channel);
  }

  bool adultSource(VideoSource source) =>
      source.classification == 'adult' ||
      adultContent(source.name) ||
      adultContent(source.displayName) ||
      adultContent(source.siteTitle ?? '') ||
      adultContent(source.endpoint.host);

  bool sourceAllowed(VideoSource source) {
    // Repositories refresh authoritative metadata. An older in-flight provider
    // must never overwrite a new adult classification with its stale snapshot.
    source = _sources.putIfAbsent(source.id, () => source);
    return !supervision.corrupted &&
        !(filterAdult && adultSource(source)) &&
        !(supervision.enabled &&
            (supervision.rules.blocksKey(sourceKey(source)) ||
                supervision.rules.blocksText(
                  '${source.displayName} ${source.name} ${source.endpoint.host}',
                )));
  }

  bool sourceIdAllowed(String id) {
    final source = _sources[id];
    return !supervision.corrupted &&
        (source == null ? !supervision.enabled : sourceAllowed(source));
  }

  bool textAllowed(String text, {String category = ''}) =>
      !supervision.corrupted &&
      !(filterAdult &&
          (adultContent(text) || adultContent(category, category: true))) &&
      !(supervision.enabled && supervision.rules.blocksText('$text $category'));

  bool itemAllowed(CatalogItem item) =>
      sourceIdAllowed(item.sourceId) &&
      textAllowed('', category: item.tags) &&
      textAllowed(
        [
          item.title,
          item.remarks,
          item.tags,
          item.description,
          ...item.lines.map((l) => l.name),
        ].join(' '),
        category: item.category,
      );

  bool channelAllowed(LiveChannel channel, {bool radio = false}) =>
      (radio || _programAllowed(channel.name)) &&
      !(supervision.enabled &&
          supervision.rules.blocksKey(
            channelKey(channel.name, radio: radio),
          )) &&
      channel.entries.every(
        (entry) => textAllowed(
          '${entry.name} ${entry.listName}',
          category: ([entry.group, ...entry.metadata.categories]).join(' / '),
        ),
      );

  void requireSource(VideoSource source) {
    if (!sourceAllowed(source)) throw const ContentBlocked();
  }

  void requireItem(CatalogItem item) {
    if (!itemAllowed(item)) throw const ContentBlocked();
  }

  void requireChannel(LiveChannel channel, {bool radio = false}) {
    if (!channelAllowed(channel, radio: radio)) throw const ContentBlocked();
  }

  void rememberCategories(String id, Map<String, String> values) {
    if (_categories.length >= 256) _categories.remove(_categories.keys.first);
    _categories[id] = (DateTime.now(), Map.unmodifiable(values));
  }

  Map<String, String>? categories(String id) {
    final saved = _categories[id];
    if (saved == null ||
        DateTime.now().difference(saved.$1) > const Duration(minutes: 10)) {
      return null;
    }
    return saved.$2;
  }

  @override
  void dispose() {
    settings.removeListener(_settingsChanged);
    supervision.removeListener(notifyListeners);
    super.dispose();
  }
}
