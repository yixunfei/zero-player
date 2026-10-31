import 'dart:io';

/// Native runners may start beside the executable, so never infer the repo
/// from their working directory or a developer's drive letter.
String fixtureProjectRoot() {
  const root = String.fromEnvironment('PROJECT_ROOT');
  if (root.isEmpty || !Directory('$root/test_support/generated').existsSync()) {
    throw StateError(
      'Pass --dart-define=PROJECT_ROOT=<repository> with generated fixtures; '
      'on Windows use tool/run_windows_native.ps1.',
    );
  }
  return root;
}
