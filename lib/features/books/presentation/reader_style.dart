import 'dart:math' as math;

import 'package:flutter/material.dart';

enum ReaderTurnMode {
  slide('横向滑动', '左右滑动或点按两侧翻页'),
  curl('仿真翻页', '从左右滑动可拖动纸页，也可点按翻页'),
  vertical('纵向分页', '上下滑动或点按上下区域翻页'),
  scroll('连续滚动', '上下滚动，到章首或章末可继续滑动切章');

  const ReaderTurnMode(this.label, this.hint);
  final String label, hint;

  bool get horizontal => this == slide || this == curl;
}

enum ReaderPaper {
  system('跟随系统'),
  white('白纸'),
  warm('暖纸'),
  green('护眼'),
  mist('雾蓝'),
  dark('夜间'),
  ink('墨黑');

  const ReaderPaper(this.label);
  final String label;

  ReaderPalette palette(ColorScheme colors) => switch (this) {
    system => ReaderPalette(colors.surface, colors.onSurface, colors.primary),
    white => const ReaderPalette(
      Color(0xfffcfcf8),
      Color(0xff262621),
      Color(0xff445942),
    ),
    warm => const ReaderPalette(
      Color(0xfff5ebd5),
      Color(0xff392e24),
      Color(0xff7b4830),
    ),
    green => const ReaderPalette(
      Color(0xffdce8d6),
      Color(0xff253326),
      Color(0xff36563e),
    ),
    mist => const ReaderPalette(
      Color(0xffe6eef0),
      Color(0xff253841),
      Color(0xff365d70),
    ),
    dark => const ReaderPalette(
      Color(0xff1b2027),
      Color(0xffe7e0d4),
      Color(0xffd9b993),
    ),
    ink => const ReaderPalette(
      Color(0xff101113),
      Color(0xffdcd9d2),
      Color(0xffbbd4cc),
    ),
  };
}

final class ReaderPalette {
  const ReaderPalette(this.paper, this.ink, this.accent);
  final Color paper, ink, accent;
  Brightness get brightness => ThemeData.estimateBrightnessForColor(paper);
}

final class ReaderPreferences {
  const ReaderPreferences({
    this.mode = ReaderTurnMode.slide,
    this.paper = ReaderPaper.system,
    this.family = 'NotoSerifSC',
    this.fontSize = 21,
    this.lineHeight = 1.8,
    this.margin = 22,
    this.texture = true,
    this.animate = true,
    this.automatic = true,
    this.status = true,
    this.immersive = true,
    this.autoEnabled = false,
    this.autoSeconds = 10,
    this.scrollSpeed = 30,
  });

  factory ReaderPreferences.fromJson(Map data) => ReaderPreferences(
    mode:
        ReaderTurnMode.values
            .where((mode) => mode.name == data['mode'])
            .firstOrNull ??
        (data['paged'] == false ? ReaderTurnMode.scroll : ReaderTurnMode.slide),
    paper:
        ReaderPaper.values
            .where((paper) => paper.name == data['paper'])
            .firstOrNull ??
        ReaderPaper.system,
    family: _fonts.containsKey(data['family'])
        ? data['family'] as String
        : 'NotoSerifSC',
    fontSize: _number(data['font'], 21, 14, 38),
    lineHeight: _number(data['line'], 1.8, 1.3, 2.4),
    margin: _number(data['margin'], 22, 12, 48),
    texture: data['texture'] != false,
    animate: data['animate'] != false,
    automatic: data['automatic'] != false,
    status: data['status'] != false,
    immersive: data['immersive'] != false,
    autoEnabled: data['autoEnabled'] == true,
    autoSeconds: _number(data['autoSeconds'], 10, 2, 120),
    scrollSpeed: _number(data['scrollSpeed'], 30, 5, 150),
  );

  final ReaderTurnMode mode;
  final ReaderPaper paper;
  final String family;
  final double fontSize, lineHeight, margin;
  final bool texture, animate, automatic, status, immersive, autoEnabled;
  final double autoSeconds, scrollSpeed;

  ReaderPreferences copyWith({
    ReaderTurnMode? mode,
    ReaderPaper? paper,
    String? family,
    double? fontSize,
    double? lineHeight,
    double? margin,
    bool? texture,
    bool? animate,
    bool? automatic,
    bool? status,
    bool? immersive,
    bool? autoEnabled,
    double? autoSeconds,
    double? scrollSpeed,
  }) => ReaderPreferences(
    mode: mode ?? this.mode,
    paper: paper ?? this.paper,
    family: family ?? this.family,
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    margin: margin ?? this.margin,
    texture: texture ?? this.texture,
    animate: animate ?? this.animate,
    automatic: automatic ?? this.automatic,
    status: status ?? this.status,
    immersive: immersive ?? this.immersive,
    autoEnabled: autoEnabled ?? this.autoEnabled,
    autoSeconds: autoSeconds ?? this.autoSeconds,
    scrollSpeed: scrollSpeed ?? this.scrollSpeed,
  );

  Map<String, Object> toJson() => {
    'mode': mode.name,
    'paper': paper.name,
    'family': family,
    'font': fontSize,
    'line': lineHeight,
    'margin': margin,
    'texture': texture,
    'animate': animate,
    'automatic': automatic,
    'status': status,
    'immersive': immersive,
    'autoEnabled': autoEnabled,
    'autoSeconds': autoSeconds,
    'scrollSpeed': scrollSpeed,
  };
}

const _fonts = {'NotoSerifSC': '宋体', 'NotoSansSC': '黑体', 'Xiaolai': '手写'};

double _number(Object? value, double fallback, double min, double max) =>
    value is num && value.isFinite
    ? value.toDouble().clamp(min, max)
    : fallback;

class ReaderPaperSurface extends StatelessWidget {
  const ReaderPaperSurface({
    super.key,
    required this.palette,
    required this.texture,
  });
  final ReaderPalette palette;
  final bool texture;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _PaperPainter(palette.paper, palette.ink, texture),
      child: const SizedBox.expand(),
    ),
  );
}

final class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.paper, this.ink, this.texture);
  final Color paper, ink;
  final bool texture;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = paper);
    if (!texture) return;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            ink.withValues(alpha: .04),
            Colors.transparent,
            Colors.transparent,
            ink.withValues(alpha: .035),
          ],
          stops: const [0, .14, .88, 1],
        ).createShader(rect),
    );
    final random = math.Random(32);
    final fiber = Paint()
      ..color = ink.withValues(alpha: .08)
      ..strokeWidth = .55;
    final count = (size.width * size.height / 330).round().clamp(0, 2400);
    for (var index = 0; index < count; index++) {
      final start = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.drawLine(
        start,
        start +
            Offset(.7 + random.nextDouble() * 1.9, random.nextDouble() - .5),
        fiber,
      );
    }
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) =>
      oldDelegate.paper != paper ||
      oldDelegate.ink != ink ||
      oldDelegate.texture != texture;
}

Future<void> showReaderSettings(
  BuildContext context,
  ReaderPreferences initial,
  ValueChanged<ReaderPreferences> onChange, {
  bool rich = false,
  bool pdf = false,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) {
    var settings = initial;
    return StatefulBuilder(
      builder: (context, update) {
        void change(ReaderPreferences next) {
          update(() => settings = next);
          onChange(next);
        }

        return FractionallySizedBox(
          heightFactor: .81,
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                Text('阅读样式', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                if (!pdf) _turnModeSettings(settings, change, rich: rich),
                ..._automationSettings(settings, change, pdf: pdf),
                const SizedBox(height: 16),
                if (!pdf) ..._paperSettings(context, settings, change),
                if (!pdf) ..._typography(settings, change),
                if (!rich)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('翻页动画'),
                    value: settings.animate,
                    onChanged: (value) =>
                        change(settings.copyWith(animate: value)),
                  ),
                if (!rich)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('显示页码与时间'),
                    value: settings.status,
                    onChanged: (value) =>
                        change(settings.copyWith(status: value)),
                  ),
                if (!rich)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('正文失败时自动换源'),
                    value: settings.automatic,
                    onChanged: (value) =>
                        change(settings.copyWith(automatic: value)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  },
);

List<Widget> _paperSettings(
  BuildContext context,
  ReaderPreferences settings,
  ValueChanged<ReaderPreferences> change,
) => [
  const Text('纸张'),
  Wrap(
    spacing: 7,
    children: [
      for (final paper in ReaderPaper.values)
        ChoiceChip(
          avatar: CircleAvatar(
            backgroundColor: paper.palette(Theme.of(context).colorScheme).paper,
          ),
          label: Text(paper.label),
          selected: settings.paper == paper,
          onSelected: (_) => change(settings.copyWith(paper: paper)),
        ),
    ],
  ),
  SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('纸面纹理'),
    value: settings.texture,
    onChanged: (value) => change(settings.copyWith(texture: value)),
  ),
];

Widget _turnModeSettings(
  ReaderPreferences settings,
  ValueChanged<ReaderPreferences> change, {
  required bool rich,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(rich ? '横排 EPUB 翻阅方式' : '翻页方式'),
    Wrap(
      spacing: 7,
      children: [
        for (final mode
            in rich
                ? [ReaderTurnMode.slide, ReaderTurnMode.scroll]
                : ReaderTurnMode.values)
          ChoiceChip(
            label: Text(
              rich && mode == ReaderTurnMode.slide ? '分段翻页' : mode.label,
            ),
            selected: rich && mode == ReaderTurnMode.slide
                ? settings.mode != ReaderTurnMode.scroll
                : settings.mode == mode,
            onSelected: (_) => change(settings.copyWith(mode: mode)),
          ),
      ],
    ),
    if (!rich) Text(settings.mode.hint),
  ],
);

List<Widget> _typography(
  ReaderPreferences settings,
  ValueChanged<ReaderPreferences> change,
) => [
  DropdownButtonFormField<String>(
    initialValue: settings.family,
    decoration: const InputDecoration(labelText: '字体'),
    items: [
      for (final entry in _fonts.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value, style: TextStyle(fontFamily: entry.key)),
        ),
    ],
    onChanged: (value) => change(settings.copyWith(family: value)),
  ),
  _StyleSlider(
    label: '字号',
    value: settings.fontSize,
    min: 14,
    max: 38,
    divisions: 24,
    onChanged: (value) => change(settings.copyWith(fontSize: value)),
  ),
  _StyleSlider(
    label: '行距',
    value: settings.lineHeight,
    min: 1.3,
    max: 2.4,
    divisions: 11,
    precision: 1,
    onChanged: (value) => change(settings.copyWith(lineHeight: value)),
  ),
  _StyleSlider(
    label: '页边距',
    value: settings.margin,
    min: 12,
    max: 48,
    divisions: 18,
    onChanged: (value) => change(settings.copyWith(margin: value)),
  ),
];

final class _StyleSlider extends StatelessWidget {
  const _StyleSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.precision = 0,
  });
  final String label;
  final double value, min, max;
  final int divisions, precision;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label),
      Expanded(
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label,
          onChanged: onChanged,
        ),
      ),
      Text(value.toStringAsFixed(precision)),
    ],
  );
}

List<Widget> _automationSettings(
  ReaderPreferences settings,
  ValueChanged<ReaderPreferences> change, {
  required bool pdf,
}) => [
  SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('全屏沉浸阅读'),
    value: settings.immersive,
    onChanged: (value) => change(settings.copyWith(immersive: value)),
  ),
  SwitchListTile(
    contentPadding: EdgeInsets.zero,
    title: const Text('自动阅读'),
    value: settings.autoEnabled,
    onChanged: (value) => change(settings.copyWith(autoEnabled: value)),
  ),
  if (settings.autoEnabled)
    _StyleSlider(
      label: '翻页间隔（秒）',
      value: settings.autoSeconds,
      min: 2,
      max: 120,
      divisions: 118,
      onChanged: (v) => change(settings.copyWith(autoSeconds: v)),
    ),
  if (settings.autoEnabled && !pdf)
    _StyleSlider(
      label: '滚动速度',
      value: settings.scrollSpeed,
      min: 5,
      max: 150,
      divisions: 29,
      onChanged: (v) => change(settings.copyWith(scrollSpeed: v)),
    ),
];
