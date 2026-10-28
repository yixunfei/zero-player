import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_services.dart';
import 'product_app.dart';

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
    final services = await AppServices.create();
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
          child: const ProductApp(),
        );
      }
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: snapshot.hasError
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('无法初始化本地数据，请检查可用空间后重试'),
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
