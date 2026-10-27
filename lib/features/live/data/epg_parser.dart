import 'package:xml/xml.dart';
import '../domain/live_channel.dart';

List<EpgProgram> parseEpg(String input) {
  if (input.contains('<!DOCTYPE') || input.contains('<!ENTITY')) {
    throw const FormatException('EPG 不允许文档类型与外部实体');
  }
  final xml = XmlDocument.parse(input);
  final result = <EpgProgram>[];
  for (final node in xml.findAllElements('programme')) {
    if (result.length >= 100000) throw const FormatException('EPG 节目数量超过限制');
    final start = xmltvTime(node.getAttribute('start') ?? '');
    final end = xmltvTime(node.getAttribute('stop') ?? '');
    final channel = node.getAttribute('channel');
    if (start == null ||
        end == null ||
        channel == null ||
        !end.isAfter(start)) {
      continue;
    }
    result.add(
      EpgProgram(
        channel,
        node.getElement('title')?.innerText ?? '未命名节目',
        start,
        end,
      ),
    );
  }
  return result;
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
