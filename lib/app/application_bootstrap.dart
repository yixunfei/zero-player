import '../core/persistence/local_open_channel.dart';
import '../features/playback/application/local_video.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_services.dart';
import 'product_app.dart';
import 'installation_introduction.dart';
import '../core/persistence/application_ownership.dart';

/// Retries service construction without registering global bindings again.
final class ApplicationBootstrap extends StatefulWidget {
  const ApplicationBootstrap({super.key});
  @override
  State<ApplicationBootstrap> createState() => _ApplicationBootstrapState();
}

final class _ApplicationBootstrapState extends State<ApplicationBootstrap> {
  late Future<AppServices> _startup = _start();
  AppServices? _services;

  Future<AppServices> _start() async {
    final AppServices services;
    try {
      services = await AppServices.create();
    } on ApplicationAlreadyRunning catch (error) {
      final path = LocalVideo.startupPath;
      if (error.directory != null &&
          path != null &&
          await LocalOpenChannel.forward(error.directory!, path)) {
        LocalVideo.startupPath = null;
        await windowManager.destroy();
      }
      rethrow;
    }
    if (!mounted) {
      await services.close();
    } else {
      _services = services;
    }
    return services;
  }

  @override
  void dispose() {
    final services = _services;
    if (services != null) unawaited(services.closeSafely());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppServices>(
    future: _startup,
    builder: (context, snapshot) {
      if (snapshot.hasData) {
        return ProviderScope(
          overrides: [servicesProvider.overrideWithValue(snapshot.data!)],
          child: InstallationIntroduction(
            services: snapshot.data!,
            child: const ProductApp(),
          ),
        );
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.error is ApplicationAlreadyRunning
                            ? '播放器已在运行，请在现有窗口打开视频；关闭后可重试。'
                            : '无法初始化本地数据，请检查可用空间后重试',
                      ),
                      FilledButton(
                        onPressed: () => setState(() {
                          _startup = _start();
                        }),
                        child: const Text('重试'),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      );
    },
  );
}
