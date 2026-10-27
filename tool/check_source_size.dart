import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';

/// Run with `dart run tool/check_source_size.dart`.
/// Uses Dart AST boundaries rather than counting braces in strings/comments.
void main() {
  var failed = false;
  for (final root in [
    'lib',
    'test',
    'integration_test',
    'tool',
    'test_support',
  ]) {
    for (final file in Directory(
      root,
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final parsed = parseFile(
        path: file.absolute.path,
        featureSet: FeatureSet.latestLanguageVersion(),
      );
      final lines = parsed.lineInfo.lineCount;
      if (lines > 1500) {
        stderr.writeln('${file.path}: $lines lines exceeds 1500');
        failed = true;
      }
      parsed.unit.accept(
        _SizeVisitor(file.path, parsed.lineInfo, () => failed = true),
      );
    }
  }
  if (failed) {
    exitCode = 1;
  } else {
    stdout.writeln('Source and function size limits passed.');
  }
}

final class _SizeVisitor extends RecursiveAstVisitor<void> {
  _SizeVisitor(this.path, this.lines, this.fail);
  final String path;
  final LineInfo lines;
  final void Function() fail;

  void check(AstNode node, String name) {
    final start = lines.getLocation(node.offset).lineNumber;
    final end = lines.getLocation(node.end).lineNumber;
    if (end - start + 1 > 100) {
      stderr.writeln(
        '$path:$start $name: ${end - start + 1} lines exceeds 100',
      );
      fail();
    }
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    check(node, node.name.lexeme);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    check(node, node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    check(node, 'constructor');
    super.visitConstructorDeclaration(node);
  }
}
