import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'app/application_bootstrap.dart';

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
  LicenseRegistry.addLicense(() async* {
    final attribution = await rootBundle.loadString(
      'assets/licenses/CONTENT-FILTER-NOTICE.txt',
    );
    for (final entry in const {
      'SenseVoiceSmall / sherpa-onnx conversion': 'FunASR-MODEL-LICENSE.txt',
      'PP-OCRv4 / RapidOCR': 'RapidOCR-LICENSE.txt',
    }.entries) {
      final license = await rootBundle.loadString(
        'assets/licenses/${entry.value}',
      );
      yield LicenseEntryWithLineBreaks([entry.key], '$attribution\n\n$license');
    }
  });
  runApp(const ApplicationBootstrap());
}
