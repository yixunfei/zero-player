import 'dart:ffi';
import 'resource_download.dart';
import 'filter_types.dart';

final class RuntimePackage {
  const RuntimePackage(this.archive, this.prefix, this.files);
  final ModelAsset archive;
  final String prefix;
  final List<ModelAsset> files;

  static RuntimePackage current() => switch (Abi.current()) {
    Abi.windowsX64 => windows,
    Abi.androidArm64 => arm64,
    Abi.androidX64 => x64,
    _ => throw const FilterFailure('此平台暂不支持可选增强识别'),
  };

  static const windows = RuntimePackage(
    ModelAsset(
      'runtime.tar.gz',
      'https://pub.dev/api/archives/sherpa_onnx_windows-2.0.1.tar.gz',
      16787852,
      '449b6ccb864713d454b771ebfe200d6e030e72cd1da9ae5bd1f079064550e435',
    ),
    'windows/x64/',
    [
      ModelAsset(
        'onnxruntime.dll',
        '',
        17799168,
        '7f66f939a881baf4f46a2216496798edf4a1429878b646d12674aa62f27d8a25',
      ),
      ModelAsset(
        'sherpa-onnx-c-api.dll',
        '',
        4294656,
        '1850fbacb36ebdc15b75e1a0353334606854ce054be4d82ca60ad6098ab8f874',
      ),
    ],
  );
  static const arm64 = RuntimePackage(
    ModelAsset(
      'runtime.tar.gz',
      'https://pub.dev/api/archives/sherpa_onnx_android_arm64-2.0.1.tar.gz',
      10448654,
      'eceb1fd5de24d07c5aa618f6fa913f3f950018e6c009b899d076ba08209d08ec',
    ),
    'android/src/main/jniLibs/arm64-v8a/',
    [
      ModelAsset(
        'libonnxruntime.so',
        '',
        22249560,
        '33847ad43bffe204699fd4a27f7f3603452a8cdaf2f9a44983a0bc31ffcf2da1',
      ),
      ModelAsset(
        'libsherpa-onnx-c-api.so',
        '',
        4484952,
        '8523d8044fb7336b945c8662821165f782103e4200a660b0ef097f6a41230e32',
      ),
    ],
  );
  static const x64 = RuntimePackage(
    ModelAsset(
      'runtime.tar.gz',
      'https://pub.dev/api/archives/sherpa_onnx_android_x86_64-2.0.1.tar.gz',
      11428967,
      'c60af7c9332382c03239ff0ad9d473e6b802067f9a1f9fbf7f1e7df93eec0143',
    ),
    'android/src/main/jniLibs/x86_64/',
    [
      ModelAsset(
        'libonnxruntime.so',
        '',
        25581120,
        '087e84297cad64acb823c3d901d6e0cc934e91add7cdb20da802cd1c0bea5c3e',
      ),
      ModelAsset(
        'libsherpa-onnx-c-api.so',
        '',
        4979072,
        'ac4321f36bdf60249d450bbce81fec6d9269a007d3c4b050bf670995c0a9dbb1',
      ),
    ],
  );
}
