import 'keyword_policy.dart';
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'local_runtime.dart';
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/network/cancellation_token.dart';
import 'filter_types.dart';
import 'promotion_evidence.dart';
import 'local_models.dart';
import 'paddle_ocr.dart';
import 'keyword_models.dart';
import 'keyword_detector.dart';
import '../hls/timeline.dart';

final class OfflineInspector implements TemporalSliceInspector {
  OfflineInspector(
    this.models, {
    this.runtime,
    this.ocr = true,
    this.asr = true,
    this.keywords,
    this.skipSeconds = 20,
  });
  final LocalRuntime? runtime;
  final bool ocr, asr;
  final KeywordModels? keywords;
  final int skipSeconds;
  final LocalModels models;
  final _messages = ReceivePort();
  final _errors = ReceivePort();
  final _exits = ReceivePort();
  final _ready = Completer<void>();
  final _exited = Completer<void>();
  final _pending = <int, Completer<FilterDecision>>{};
  SendPort? _worker;
  Isolate? _isolate;
  Future<void>? _preparing;
  Future<void>? _closing;
  String? _failure;
  int _nextId = 0;

  @override
  void reset() => _worker?.send({'reset': true});

  @override
  Future<void> prepare(CancellationToken cancellation) =>
      _preparing ??= _prepare(cancellation);

  Future<void> _prepare(CancellationToken token) async {
    if (!ocr && !asr && keywords == null) {
      throw const FilterFailure('未选择增强识别能力');
    }
    await runtime?.ensure(token);
    await models.ensure(token, ocr: ocr, asr: asr);
    await keywords?.ensure(token);
    token.check();
    _messages.listen(_receive);
    _errors.listen((_) => _fail('离线识别线程异常，已停止放行'));
    _exits.listen((_) {
      if (!_exited.isCompleted) _exited.complete();
      if (_closing == null) _fail('离线识别线程已退出');
    });
    final cancelled = Completer<void>();
    final remove = token.listen(() {
      if (!cancelled.isCompleted) {
        cancelled.completeError(const RequestCancelled());
      }
    });
    final ready = Future.any([_ready.future, cancelled.future]);
    try {
      await Future.wait<void>([
        Isolate.spawn(
          _detectMain,
          [
            _messages.sendPort,
            models.directory.path,
            runtime?.directory.path ?? '',
            ocr,
            asr,
            keywords?.directory.path ?? '',
            skipSeconds,
          ],
          onError: _errors.sendPort,
          onExit: _exits.sendPort,
        ).then((isolate) {
          _isolate = isolate;
        }),
        ready.timeout(
          const Duration(seconds: 90),
          onTimeout: () => throw const FilterFailure('离线模型加载超时，已停止播放'),
        ),
      ]);
      token.check();
    } finally {
      remove();
    }
  }

  void _receive(dynamic message) {
    if (message is SendPort) {
      _worker = message;
      if (_closing != null) _worker!.send({'close': true});
      return;
    }
    final map = message as Map;
    if (map['ready'] == true) {
      if (!_ready.isCompleted) _ready.complete();
      return;
    }
    if (map['id'] == null) {
      _fail(map['error'] as String);
      return;
    }
    final pending = _pending.remove(map['id']);
    if (pending == null || pending.isCompleted) return;
    if (map['error'] != null) {
      pending.completeError(FilterFailure(map['error'] as String));
    } else {
      pending.complete(
        FilterDecision(
          FilterVerdict.values[map['verdict'] as int],
          reason: map['reason'] as String,
          requiresConfirmation: true,
          ranges: (map['ranges'] as List? ?? [])
              .map(
                (r) => RemovedInterval(
                  Duration(milliseconds: r[0] as int),
                  Duration(milliseconds: r[1] as int),
                ),
              )
              .toList(),
        ),
      );
    }
  }

  void _fail(String message) {
    _failure = message;
    if (!_ready.isCompleted) _ready.completeError(FilterFailure(message));
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(FilterFailure(message));
    }
    _pending.clear();
  }

  @override
  Future<FilterDecision> inspect(
    MediaSlice slice,
    CancellationToken token,
  ) async {
    token.check();
    if (_failure != null) throw FilterFailure(_failure!);
    if (_closing != null || _worker == null) {
      throw const FilterFailure('离线检测器尚未就绪');
    }
    final id = _nextId++;
    final pending = Completer<FilterDecision>();
    _pending[id] = pending;
    final remove = token.listen(() {
      if (!pending.isCompleted) pending.completeError(const RequestCancelled());
    });
    _worker!.send({
      'id': id,
      'frames': slice.frames.map((f) => f.path).toList(),
      'audio': slice.audio?.path,
      'startMs': slice.start.inMilliseconds,
      'durationMs': slice.duration.inMilliseconds,
    });
    try {
      return await pending.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw const FilterFailure('离线检测超时，已停止放行'),
      );
    } finally {
      remove();
      _pending.remove(id);
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    if (_isolate != null) {
      _worker?.send({'close': true});
      // Native inference owns its buffers until it returns; never free models
      // from another isolate while a native call is using them.
      await _exited.future;
    }
    _messages.close();
    _errors.close();
    _exits.close();
  }
}

void _detectMain(List<Object> arguments) {
  final output = arguments[0] as SendPort;
  final directory = arguments[1] as String;
  PaddleOcr? ocr;
  sherpa.OfflineRecognizer? speech;
  KeywordDetector? keywords;
  // Publish the shutdown channel before native model loading. A close request
  // received during loading is queued until the native call safely returns.
  final input = ReceivePort();
  output.send(input.sendPort);
  try {
    final runtime = arguments[2] as String;
    if (runtime.isNotEmpty) {
      DynamicLibrary.open(
        '$runtime/${Platform.isWindows ? 'onnxruntime.dll' : 'libonnxruntime.so'}',
      );
    }
    if (arguments[3] as bool) ocr = PaddleOcr(directory);
    if ((arguments[5] as String).isNotEmpty) {
      sherpa.initBindings(runtime);
      keywords = KeywordDetector(arguments[5] as String, runtime);
    }
    if (arguments[4] as bool) {
      sherpa.initBindings(runtime.isEmpty ? null : runtime);
      speech = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: sherpa.OfflineModelConfig(
            senseVoice: sherpa.OfflineSenseVoiceModelConfig(
              model: '$directory/speech.onnx',
              language: 'auto',
              useInverseTextNormalization: true,
            ),
            tokens: '$directory/tokens.txt',
            numThreads: 1,
            debug: false,
          ),
        ),
      );
    }
    output.send({'ready': true});
    input.listen((dynamic request) {
      final map = request as Map;
      if (map['reset'] == true) {
        keywords?.reset();
        return;
      }
      if (map['close'] == true) {
        speech?.free();
        ocr?.close();
        keywords?.close();
        input.close();
        return;
      }
      try {
        final decision = _inspectRequest(
          map,
          ocr,
          speech,
          keywords,
          arguments[6] as int,
        );
        output.send({
          'id': map['id'],
          'verdict': decision.verdict.index,
          'reason': decision.reason,
          'ranges': decision.ranges
              .map((r) => [r.start.inMilliseconds, r.end.inMilliseconds])
              .toList(),
        });
      } catch (error) {
        output.send({
          'id': map['id'],
          'error': error is FilterFailure ? error.message : '离线识别失败，已停止放行',
        });
      }
    });
  } catch (_) {
    speech?.free();
    ocr?.close();
    keywords?.close();
    input.close();
    output.send({'error': '离线模型无法加载，请检查模型文件与运行环境'});
  }
}

FilterDecision _inspectRequest(
  Map request,
  PaddleOcr? ocr,
  sherpa.OfflineRecognizer? speech,
  KeywordDetector? keywords,
  int skipSeconds,
) {
  final frames = (request['frames'] as List).cast<String>();
  final audio = request['audio'] as String?;
  final start = Duration(milliseconds: request['startMs'] as int);
  final span = Duration(seconds: skipSeconds);
  if (keywords != null && audio != null) {
    final hit = keywords.inspect(audio, startMs: start.inMilliseconds);
    if (hit != null &&
        const KeywordPolicy().evaluate([
              ContentEvidence(text: hit.word, source: EvidenceSource.speech),
            ]).verdict ==
            FilterVerdict.block &&
        hit.offset.inMilliseconds < (request['durationMs'] as int)) {
      return FilterDecision(
        FilterVerdict.block,
        reason: '命中常见词：${hit.word}',
        ranges: [
          RemovedInterval(start + hit.offset, start + hit.offset + span),
        ],
      );
    }
  }
  return inspectPromotionEvidence(
    _promotionEvidence(frames, audio, start, ocr, speech),
    span,
  );
}

Iterable<(Duration, Iterable<ContentEvidence>)> _promotionEvidence(
  List<String> frames,
  String? audio,
  Duration start,
  PaddleOcr? ocr,
  sherpa.OfflineRecognizer? speech,
) sync* {
  if (ocr != null) {
    for (final (index, frame) in frames.indexed) {
      yield (start + Duration(milliseconds: index * 500), ocr.recognize(frame));
    }
  }
  if (audio == null || speech == null) return;
  final wave = sherpa.readWave(audio);
  if (wave.samples.isEmpty || wave.sampleRate != 16000) {
    throw const FilterFailure('音频样本无效，无法完成语音检测');
  }
  yield (
    start,
    [
      ContentEvidence(
        text: _recognizeSpeech(speech, wave.samples, wave.sampleRate),
        source: EvidenceSource.speech,
      ),
    ],
  );
}

String _recognizeSpeech(
  sherpa.OfflineRecognizer speech,
  Float32List samples,
  int sampleRate,
) {
  final stream = speech.createStream();
  try {
    stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
    speech.decode(stream);
    return speech.getResult(stream).text;
  } finally {
    stream.free();
  }
}
