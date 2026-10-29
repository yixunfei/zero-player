import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/features/supervision/domain/content_classification.dart';
import 'package:zero_player/features/supervision/domain/supervision_rules.dart';

void main() {
  test(
    'adult labels survive traditional characters, full width and obfuscation',
    () {
      for (final value in [
        '倫理片',
        '無 碼',
        'Ｒ１８',
        'Japan ＡＶ channel',
        'P\u200born',
        '18 +',
        '里番',
        '成人视频',
        '无码中字',
        '91porn.com',
      ]) {
        expect(adultContent(value), isTrue, reason: value);
      }
      for (final value in [
        '日韩伦理',
        '電影 / 倫理',
        '有码',
        '香港三級',
        '韩国伦理,剧情',
        '日韩伦理 / 动作',
        '劇情；香港三級|喜劇',
      ]) {
        expect(adultContent(value, category: true), isTrue, reason: value);
      }
    },
  );
  test('ordinary and identity-related terms are not broadly censored', () {
    for (final value in [
      '成人教育',
      '成人礼',
      '有码头的城市',
      'Java 入门',
      '美女与野兽',
      '同性婚姻纪录片',
      '福利政策',
      '写真摄影教程',
      'AV1 高清编码',
    ]) {
      expect(adultContent(value), isFalse, reason: value);
      expect(adultContent(value, category: true), isFalse, reason: value);
    }
  });
  test(
    'custom rules match literal normalized words, never executable regex',
    () {
      final rules = SupervisionRules(keywords: ['ＡＢＣ', '無碼', 'a.*b']);
      expect(rules.blocksText('a-b_c 频道'), isTrue);
      expect(rules.blocksText('无码'), isTrue);
      expect(rules.blocksText('axxxxxb'), isFalse);
      expect(() => SupervisionRules(keywords: ['.*']), throwsFormatException);
      expect(
        () => SupervisionRules(keywords: List.filled(201, 'x')),
        throwsFormatException,
      );
    },
  );
}
