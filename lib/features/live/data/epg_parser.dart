import 'dart:isolate';
import 'package:xml/xml_events.dart';
import '../domain/live_channel.dart';

Future<({List<EpgProgram> programs, Map<String, List<String>> names})>
parseEpgGuideInBackground(String input, DateTime now) => Isolate.run(
  () => _readGuide(
    input,
    now.subtract(const Duration(days: 1)),
    now.add(const Duration(days: 7)),
  ),
);

Future<List<EpgProgram>> parseEpgInBackground(String input, DateTime now) =>
    Isolate.run(
      () => parseEpg(
        input,
        from: now.subtract(const Duration(days: 1)),
        until: now.add(const Duration(days: 7)),
      ),
    );

List<EpgProgram> parseEpg(String input, {DateTime? from, DateTime? until}) {
  return _readGuide(input, from, until).programs;
}

({List<EpgProgram> programs, Map<String, List<String>> names}) _readGuide(
  String input,
  DateTime? from,
  DateTime? until,
) {
  if (input.contains('<!DOCTYPE') || input.contains('<!ENTITY')) {
    throw const FormatException('EPG 不允许文档类型与外部实体');
  }
  final reader = _EpgReader(from, until);
  for (final event in parseEvents(
    input,
    validateNesting: true,
    validateDocument: true,
  )) {
    reader.add(event);
  }
  return (programs: reader.programs, names: reader.names);
}

final class _EpgReader {
  _EpgReader(this.from, this.until);
  final DateTime? from;
  final DateTime? until;
  final programs = <EpgProgram>[];
  int _depth = 0;
  int _count = 0;
  int? _programmeDepth;
  int? _titleDepth;
  Map<String, String>? _attributes;
  StringBuffer? _title;
  final names = <String, List<String>>{};
  String? _channelId;
  int? _channelDepth, _displayDepth;
  StringBuffer? _display;

  void add(XmlEvent event) {
    if (event is XmlStartElementEvent) {
      _depth++;
      if (event.name == 'channel' &&
          _channelDepth == null &&
          _programmeDepth == null) {
        if (names.length >= 10000) throw const FormatException('EPG 频道数量超过限制');
        _channelId = event.attributes
            .where((a) => a.name == 'id')
            .firstOrNull
            ?.value;
        _channelDepth = _depth;
      } else if (event.name == 'display-name' &&
          _depth == (_channelDepth ?? -2) + 1) {
        _displayDepth = _depth;
        _display = StringBuffer();
      }
      if (event.name == 'programme' && _programmeDepth == null) {
        if (++_count > 100000) throw const FormatException('EPG 节目数量超过限制');
        _programmeDepth = _depth;
        _attributes = {
          for (final attribute in event.attributes)
            attribute.name: attribute.value,
        };
      } else if (event.name == 'title' &&
          _depth == (_programmeDepth ?? -2) + 1 &&
          _title == null) {
        _titleDepth = _depth;
        _title = StringBuffer();
      }
      if (event.isSelfClosing) _end();
    } else if (event is XmlEndElementEvent) {
      _end();
    } else if (_displayDepth != null) {
      if (event is XmlTextEvent) _display!.write(event.value);
      if (event is XmlCDATAEvent) _display!.write(event.value);
    } else if (_titleDepth != null) {
      if (event is XmlTextEvent) _title!.write(event.value);
      if (event is XmlCDATAEvent) _title!.write(event.value);
    }
  }

  void _end() {
    if (_depth == _displayDepth) {
      if (_channelId != null && _display!.isNotEmpty) {
        names
            .putIfAbsent(_channelId!, () => [])
            .add(_display.toString().trim());
      }
      _displayDepth = null;
      _display = null;
    }
    if (_depth == _channelDepth) {
      _channelDepth = null;
      _channelId = null;
    }
    if (_depth == _titleDepth) _titleDepth = null;
    if (_depth == _programmeDepth) {
      _complete();
      _programmeDepth = null;
      _attributes = null;
      _title = null;
    }
    _depth--;
  }

  void _complete() {
    final start = xmltvTime(_attributes!['start'] ?? '');
    final end = xmltvTime(_attributes!['stop'] ?? '');
    final channel = _attributes!['channel'];
    if (start == null ||
        end == null ||
        channel == null ||
        !end.isAfter(start) ||
        (from != null && !end.isAfter(from!)) ||
        (until != null && !start.isBefore(until!))) {
      return;
    }
    programs.add(
      EpgProgram(channel, _title?.toString() ?? '未命名节目', start, end),
    );
  }
}

DateTime? xmltvTime(String text) {
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})\s*(?:([+-])(\d{2})(\d{2})|Z)?$',
  ).firstMatch(text.trim());
  if (match == null) return null;
  final values = [for (var i = 1; i <= 6; i++) int.parse(match[i]!)];
  final date = DateTime.utc(
    values[0],
    values[1],
    values[2],
    values[3],
    values[4],
    values[5],
  );
  if (date.month != values[1] ||
      date.day != values[2] ||
      values[3] > 23 ||
      values[4] > 59 ||
      values[5] > 59) {
    return null;
  }
  final hours = int.tryParse(match[8] ?? '0') ?? 0;
  final minutes = int.tryParse(match[9] ?? '0') ?? 0;
  if (hours > 23 || minutes > 59) return null;
  final offset = Duration(
    minutes: (hours * 60 + minutes) * (match[7] == '-' ? -1 : 1),
  );
  // XMLTV specifies UTC if no explicit offset is present.
  return date.subtract(offset);
}
