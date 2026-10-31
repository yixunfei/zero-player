import 'package:path/path.dart' as p;

const videoExtensions = [
  'mp4',
  'mkv',
  'avi',
  'mov',
  'wmv',
  'flv',
  'webm',
  'm4v',
  'ts',
  'm2ts',
  'mpg',
  'mpeg',
  '3gp',
  'ogv',
];

bool isLocalVideo(String path) => videoExtensions.contains(
  p.extension(path).toLowerCase().replaceFirst('.', ''),
);
