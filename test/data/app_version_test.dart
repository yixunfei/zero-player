import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zero_player/app/app_version.dart';

void main() {
  test('settings and diagnostic versions match the release manifest', () {
    final manifest = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(manifest)!.group(1);
    expect(appBuildVersion, version);
  });
}
