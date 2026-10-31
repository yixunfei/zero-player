import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'keyword_models.dart';
import 'keyword_audio_context.dart';

/// Standalone speech uses strong terms only. Contextual words remain in the
/// OCR/ASR policy; resetting a stream to discard weak KWS hits loses timing.
const commonKeywordTokens = '''
x īn p ú j īng @新葡京
d ǔ ch ǎng @赌场
b ó c ǎi @博彩
b ǎi j iā l è @百家乐
x iàn j īn w ǎng @现金网
''';

final class KeywordDetection {
  const KeywordDetection(this.word, this.offset);
  final String word;
  final Duration offset;
}

/// Lives exclusively inside the inference isolate. The public Dart wrapper
/// drops timestamps, so read the documented C JSON result from the same DLL.
final class KeywordDetector {
  KeywordDetector(String directory, String runtime) {
    final library = DynamicLibrary.open(
      '$runtime/${Platform.isWindows ? 'sherpa-onnx-c-api.dll' : 'libsherpa-onnx-c-api.so'}',
    );
    _result = library
        .lookupFunction<
          Pointer<Uint8> Function(Pointer<Void>, Pointer<Void>),
          Pointer<Uint8> Function(Pointer<Void>, Pointer<Void>)
        >('SherpaOnnxGetKeywordResultAsJson');
    _free = library
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('SherpaOnnxFreeKeywordResultJson');
    _spotter = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '$directory/${KeywordModels.assets[0].name}',
            decoder: '$directory/${KeywordModels.assets[1].name}',
            joiner: '$directory/${KeywordModels.assets[2].name}',
          ),
          tokens: '$directory/tokens.txt',
          numThreads: 1,
          debug: false,
          provider: 'cpu',
        ),
        keywordsBuf: commonKeywordTokens,
        keywordsBufSize: utf8.encode(commonKeywordTokens).length,
        keywordsThreshold: .3,
      ),
    );
  }
  late final sherpa.KeywordSpotter _spotter;
  late final Pointer<Uint8> Function(Pointer<Void>, Pointer<Void>) _result;
  late final void Function(Pointer<Uint8>) _free;
  final _context = KeywordAudioContext();
  int _suppressUntilMs = -1;

  void reset() {
    _context.reset();
    _suppressUntilMs = -1;
  }

  KeywordDetection? inspect(String audio, {int? startMs}) {
    final wave = sherpa.readWave(audio);
    if (wave.sampleRate != 16000) throw const FormatException('关键词音频必须为 16kHz');
    final context = _context.append(wave.samples, startMs);
    if (!context.continuous) _suppressUntilMs = -1;
    final stream = _spotter.createStream();
    try {
      stream.acceptWaveform(
        samples: context.samples,
        sampleRate: wave.sampleRate,
      );
      stream.acceptWaveform(samples: Float32List(8000), sampleRate: 16000);
      stream.inputFinished();
      while (_spotter.isReady(stream)) {
        _spotter.decode(stream);
        final hit = _readResult(stream);
        if (hit != null) {
          final offset = hit.offset - Duration(milliseconds: context.prefixMs);
          final absoluteMs = (startMs ?? 0) + offset.inMilliseconds;
          if (absoluteMs >= _suppressUntilMs) {
            _suppressUntilMs = absoluteMs + 1500;
            return KeywordDetection(hit.word, offset);
          }
          _spotter.reset(stream);
        }
      }
      return null;
    } finally {
      stream.free();
    }
  }

  KeywordDetection? _readResult(sherpa.OnlineStream stream) {
    final pointer = _result(_spotter.ptr.cast(), stream.ptr.cast());
    if (pointer == nullptr) return null;
    try {
      var length = 0;
      while (length < 65536 && pointer[length] != 0) {
        length++;
      }
      if (length == 65536) throw const FormatException('关键词结果长度无效');
      final data = jsonDecode(utf8.decode(pointer.asTypedList(length))) as Map;
      final word = data['keyword'] as String? ?? '';
      if (word.isEmpty) return null;
      final times = (data['timestamps'] as List).cast<num>();
      if (times.isEmpty) throw const FormatException('关键词结果缺少起点');
      final seconds =
          (data['start_time'] as num).toDouble() + times.first.toDouble();
      if (!seconds.isFinite || seconds < 0) {
        throw const FormatException('关键词时间无效');
      }
      return KeywordDetection(
        word,
        Duration(milliseconds: (seconds * 1000).round()),
      );
    } finally {
      _free(pointer);
    }
  }

  void close() => _spotter.free();
}
