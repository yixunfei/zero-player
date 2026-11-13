String audiobookExtension(List<int> bytes, {bool isM4b = false}) {
  if (bytes.length < 64) throw const FormatException('音频文件不完整');
  bool at(int offset, String signature) => signature.codeUnits.indexed.every(
    (part) => bytes[offset + part.$1] == part.$2,
  );
  if (at(0, 'RIFF') && at(8, 'WAVE')) return 'wav';
  if (at(0, 'fLaC')) return 'flac';
  if (at(0, 'OggS') && (at(28, 'OpusHead') || at(29, 'vorbis'))) return 'ogg';
  if (at(4, 'ftyp') &&
      (at(8, 'M4A ') || at(8, 'M4B ') || (isM4b && at(8, 'mp42')))) {
    return 'm4a';
  }
  if (at(0, 'ID3') ||
      (bytes[0] == 255 && bytes[1] & 0xe0 == 0xe0 && bytes[1] & 0x06 != 0)) {
    return 'mp3';
  }
  if (bytes[0] == 255 && bytes[1] & 0xf6 == 0xf0) return 'aac';
  throw const FormatException('来源没有返回受支持的直连音频文件');
}
