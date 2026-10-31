import 'dart:io';
import 'package:zero_player/core/persistence/local_open_channel.dart';

Future<void> main(List<String> args) async {
  final accepted = await LocalOpenChannel.forward(Directory(args[0]), args[1]);
  exit(accepted ? 0 : 1);
}
