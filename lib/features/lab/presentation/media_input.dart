import 'package:flutter/material.dart';

import '../application/lab_controller.dart';

final class MediaInput extends StatefulWidget {
  const MediaInput({super.key, required this.controller});
  final LabController controller;
  @override
  State<MediaInput> createState() => _MediaInputState();
}

final class _MediaInputState extends State<MediaInput> {
  final _address = TextEditingController();
  static const _fixtureBase = String.fromEnvironment(
    'FIXTURE_BASE',
    defaultValue: 'http://127.0.0.1:9763',
  );

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('打开媒体', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextField(
            controller: _address,
            key: const ValueKey('media-url'),
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: '媒体地址',
              hintText: 'https://…/index.m3u8',
            ),
            onSubmitted: widget.controller.open,
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用本机网关'),
            subtitle: const Text('HLS 改写与共享分片缓存'),
            value: widget.controller.useGateway,
            onChanged: widget.controller.setGateway,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.controller.opening
                ? null
                : () => widget.controller.open(_address.text),
            icon: const Icon(Icons.play_arrow),
            label: const Text('播放媒体'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          Text('受控样本', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _sample('HLS · TS', 'master.m3u8'),
              _sample('HLS · fMP4', 'fmp4/index.m3u8'),
              _sample('HLS · AES-128', 'aes/index.m3u8'),
              _sample('MP4', 'sample.mp4'),
              _sample('HTTP-FLV', 'sample.flv'),
            ],
          ),
          const SizedBox(height: 16),
          const Text('样本需要启动本机 fixture 服务。模拟器通过 adb reverse 连接；普通媒体播放不需要该服务。'),
        ],
      ),
    ),
  );

  Widget _sample(String title, String path) => OutlinedButton(
    onPressed: widget.controller.opening
        ? null
        : () {
            _address.text = '$_fixtureBase/$path';
            widget.controller.open(_address.text);
          },
    child: Text(title),
  );
}
