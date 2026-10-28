import '../../../app/app_fonts.dart';

void validateSetting(String key, Object? value) {
  final choices = <String, Set<String>>{
    'font': appFontLabels.keys.toSet(),
    'theme': {'cinema', 'dark', 'light', 'system'},
    'mode': {'auto', 'television'},
    'recommendation': {'douban', 'off'},
    'homeLayout': {'single', 'aggregate'},
  };
  if (choices.containsKey(key)) {
    if (!choices[key]!.contains(value)) throw const FormatException('设置选项无效');
  } else if (key == 'manualLoadCount') {
    if (value is! int || value < 12 || value > 240) {
      throw const FormatException('加载数量无效');
    }
  } else if (key == 'homeChannel') {
    if (value is! String || value.length > 128) {
      throw const FormatException('默认频道无效');
    }
  } else if ({
    'searchConcurrency',
    'probeConcurrency',
    'downloadConcurrency',
  }.contains(key)) {
    final max = key == 'searchConcurrency'
        ? 16
        : key == 'probeConcurrency'
        ? 6
        : 4;
    if (value is! int || value < 1 || value > max) {
      throw const FormatException('并发设置无效');
    }
  } else if (key == 'prefetchSegments') {
    if (value is! int || value < 0 || value > 10) {
      throw const FormatException('预取设置无效');
    }
  } else if ({'cacheMiB', 'episodeCacheMiB', 'downloadMiB'}.contains(key)) {
    final minimum = key == 'downloadMiB' ? 128 : 64;
    final maximum = key == 'downloadMiB'
        ? 1048576
        : key == 'cacheMiB'
        ? 16384
        : 2048;
    if (value is! int || value < minimum || value > maximum) {
      throw const FormatException('容量设置无效');
    }
  } else if ({
    'backgroundProbe',
    'startFullscreen',
    'navigationGuideSeen',
    'autoDownloadFallback',
    'multiSourceDownload',
    'gestures',
    'autoplay',
    'cache',
    'skip',
    'adFilter',
    'filterAdult',
    'allowMetered',
    'cacheWhilePaused',
  }.contains(key)) {
    if (value is! bool) throw const FormatException('开关设置无效');
  } else {
    throw const FormatException('未知设置字段');
  }
}
