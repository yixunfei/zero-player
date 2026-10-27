import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app_services.dart';
import 'app/product_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Xiaolai',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    for (final font in ['NotoSans', 'NotoSerif']) {
      yield LicenseEntryWithLineBreaks([
        font,
      ], await rootBundle.loadString('assets/fonts/$font-OFL.txt'));
    }
  });
  try {
    final services = await AppServices.create();
    runApp(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const ProductApp(),
      ),
    );
  } catch (_) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('无法初始化本地数据，请检查可用空间后重试'),
                FilledButton(onPressed: main, child: const Text('重试')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
