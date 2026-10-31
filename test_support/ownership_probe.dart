import 'dart:convert';
import 'dart:io';
import 'package:zero_player/core/persistence/application_ownership.dart';

Future<void> main(List<String> args) async {
  final owner = await ApplicationOwnership.acquire(Directory(args.single));
  stdout.writeln('locked');
  final command = await stdin.transform(utf8.decoder).first;
  if (command.trim() == 'crash') exit(17);
  await owner.close();
}
