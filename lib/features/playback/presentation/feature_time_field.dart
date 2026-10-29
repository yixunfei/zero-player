import 'package:flutter/material.dart';
import '../domain/feature_time.dart';

final class FeatureTimeField extends StatelessWidget {
  const FeatureTimeField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
    required this.currentTime,
  });
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final VoidCallback onChanged;
  final int Function() currentTime;

  String _comparison() {
    try {
      return '${(parseFeatureTime(controller.text) / 1000).toStringAsFixed(3)} 秒';
    } on FormatException {
      return '格式：05:55.5 或 1:05:55.5';
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: TextInputType.datetime,
        decoration: InputDecoration(
          labelText: label,
          helperText: _comparison(),
        ),
        onChanged: (_) => onChanged(),
      ),
      TextButton.icon(
        onPressed: !enabled
            ? null
            : () {
                controller.text = featureTimeText(currentTime());
                onChanged();
              },
        icon: const Icon(Icons.my_location, size: 16),
        label: const Text('使用当前播放时间'),
      ),
    ],
  );
}
