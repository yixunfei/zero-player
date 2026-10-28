import '../../live/domain/live_channel.dart';

enum RadioCategory {
  radio('广播电台'),
  television('电视伴听');

  const RadioCategory(this.label);
  final String label;
}

RadioCategory radioCategory(LiveChannel station) {
  final name = station.name;
  if (RegExp(r'伴音|伴听|电视音频').hasMatch(name)) {
    return RadioCategory.television;
  }
  // A radio station can belong to a broadcaster named “广播电视台”.
  final radioName = name.replaceAll('广播电视台', '');
  if (RegExp(
    r'广播|电台|之声|radio|\b(?:CNR|CRI|FM|AM)(?:\b|\d|[-\s])',
    caseSensitive: false,
  ).hasMatch(radioName)) {
    return RadioCategory.radio;
  }
  if (RegExp(
        r'^(?:CCTV|CGTN|CETV|BTV)|卫视|TVB|翡翠台|明珠台|电视台|电视频道',
        caseSensitive: false,
      ).hasMatch(radioName) ||
      RegExp(r'电视伴听|电视伴音|^TV$', caseSensitive: false).hasMatch(station.group)) {
    return RadioCategory.television;
  }
  return RadioCategory.radio;
}

int compareRadioStations(LiveChannel a, LiveChannel b) {
  final category = radioCategory(a).index.compareTo(radioCategory(b).index);
  if (category != 0) return category;
  if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
  final name = a.name.compareTo(b.name);
  return name != 0 ? name : a.id.compareTo(b.id);
}
