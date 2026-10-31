import 'filter_types.dart';

/// Screen size is measured against the decoded frame, not OCR crop dimensions.
/// Geographic words alone in ordinary dialogue are not promotional evidence.
final class KeywordPolicy {
  const KeywordPolicy();

  static const _strong = ['新葡京', '赌场', '博彩', '百家乐', '赌城', '现金网'];
  static const _contextual = ['澳门', '缅北', '真人'];
  static const _promotion = [
    '下注',
    '充值',
    '返利',
    '返水',
    '送彩金',
    '开户',
    '投注',
    '荷官',
    '在线',
    '娱乐',
  ];

  FilterDecision evaluate(Iterable<ContentEvidence> evidence) {
    FilterDecision? uncertain;
    for (final item in evidence) {
      final text = normalize(item.text);
      if (text.isEmpty) continue;
      final prominent =
          item.source == EvidenceSource.screen && item.heightRatio >= 0.055;
      final strong = _strong.where(text.contains).firstOrNull;
      final contextual = _contextual.where(text.contains).firstOrNull;
      final promotional = _promotion.any(text.contains);
      final address = RegExp(r'www[.．。a-z0-9]').hasMatch(text);
      final matched =
          strong ??
          (contextual != null && (prominent || promotional)
              ? contextual
              : null) ??
          (prominent && address ? '推广网址' : null);
      if (matched == null) continue;
      if (!item.confidence.isFinite ||
          item.confidence < 0.72 ||
          item.confidence > 1) {
        uncertain = const FilterDecision(
          FilterVerdict.uncertain,
          reason: '发现疑似推广内容，识别置信度不足，已停止放行',
        );
        continue;
      }
      return FilterDecision(FilterVerdict.block, reason: '命中推广特征：$matched');
    }
    return uncertain ?? const FilterDecision(FilterVerdict.allow);
  }

  static String normalize(String text) {
    final buffer = StringBuffer();
    for (var code in text.toLowerCase().runes) {
      if (code >= 0xff01 && code <= 0xff5e) code -= 0xfee0;
      buffer.writeCharCode(code);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[\s\u200b-\u200d\ufeff]'), '')
        .replaceAll('澳門', '澳门')
        .replaceAll('緬北', '缅北')
        .replaceAll('賭場', '赌场')
        .replaceAll('賭城', '赌城')
        .replaceAll('娛樂', '娱乐')
        .replaceAll('現金', '现金')
        .replaceAll('百家樂', '百家乐')
        .replaceAll('開戶', '开户')
        .replaceAll('線上', '在线')
        .replaceAll(
          RegExp(r'(?<=[\u4e00-\u9fff])[·•._-]+(?=[\u4e00-\u9fff])'),
          '',
        );
  }
}
