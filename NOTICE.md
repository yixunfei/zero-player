# Third-party notices

Zero Player source: Copyright (C) 2026 Zero Player contributors, AGPL-3.0-or-later. See LICENSE.

## Functional reference

LibreTV 2.21.0, commit deb72fa01f199abbb6e404c4a3e976aabfe4c96c:
https://github.com/LibreSpark/LibreTV/tree/deb72fa01f199abbb6e404c4a3e976aabfe4c96c
License: AGPL-3.0-or-later. Flutter/Dart implementation written independently; source format and ranking API protocol facts checked against the baseline, including src/lib/douban-weekly.ts. No upstream TypeScript implementation is bundled. Candidate snapshots retain source URLs and dates; their inclusion does not certify availability or media rights.

## Dart and Flutter

Packages retain their licenses. The application exposes Flutter LicenseRegistry. tool/collect_notices.py gathers installed package license/notice files and an inventory into artifacts/notices. pubspec.lock records exact versions. Collection is not a claim that all transitive native license obligations have been discharged.

## Native components

- media_kit Dart/plugin wrappers: MIT, https://github.com/media-kit/media-kit
- Windows libmpv: media-kit/libmpv-win32-video-build release 2023-09-24, mpv-dev-x86_64-20230924-git-652a1dd.7z. Build sources: https://github.com/media-kit/libmpv-win32-video-build. mpv/FFmpeg build options determine GPL/LGPL obligations; do not describe the complete binary bundle as MIT.
- Android libmpv: media-kit/libmpv-android-video-build v1.1.7. Build sources: https://github.com/media-kit/libmpv-android-video-build.
- ANGLE Windows bundle v1.0.1: https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES. ANGLE upstream: https://chromium.googlesource.com/angle/angle. Includes third-party graphics libraries with their own licenses.
- FFmpegKit Windows 8.1.2 min: https://github.com/sk3llo/ffmpeg_kit_flutter/releases/tag/8.1.2-min. Bundled LICENSES directory preserves the supplier's full notices, source links, DLL hashes and build scripts. FFmpeg shared libraries LGPL-2.1-or-later; FFmpegKit LGPL-3.0 per supplier notice.
- Android FFmpegKit Maven com.antonkarpenko:ffmpeg-kit-min:2.2.3; Flutter wrapper ffmpeg_kit_flutter_new_min 3.6.7. https://github.com/sk3llo/ffmpeg_kit_flutter_android. Minimal variant selected; the Maven POM identifies the min branch; source JAR and build sources accompany the release.
- SQLite native binaries: sqlite3.dart 3.5.2, https://github.com/simolus3/sqlite3.dart; SQLite is public domain, wrapper license retained.
- Visual C++ runtime DLLs are copied from the installed VS2022 redistributable directory under Microsoft's redistributable terms; they are not covered by this project's AGPL.

The v0.0.1 release includes dependency notices and records of native source/build repositories. Android uses a dedicated local release certificate. Upstream native binaries are redistributed unmodified; retain their licenses and corresponding-source/build references. This collection is not represented as an independent legal or complete supply-chain audit.

Synthetic color bars and tones in tests are project-generated. Development FFmpeg command-line tools and downloaded reference source are not included in the application source archive.

## Offline content filtering

- Optional keyword spotting weights: sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20, published by k2-fsa / sherpa-onnx at https://github.com/k2-fsa/sherpa-onnx/releases/tag/kws-models . Only the quantized chunk-16 encoder/joiner, decoder and token vocabulary are installed. The downloaded archive does not contain a separate model-weight license; the toolkit's Apache-2.0 license is not asserted here as a license grant for these weights. Exact source, archive and extracted-file hashes are pinned in lib/media/content_filter/keyword_models.dart. Weights are not included in the base application or source archive.
- sherpa_onnx 2.0.1: Apache-2.0, https://github.com/k2-fsa/sherpa-onnx. An explicitly downloaded, pinned platform archive supplies the optional shared ONNX Runtime 1.28.2 library.
- ONNX Runtime: MIT, https://github.com/microsoft/onnxruntime. onnxruntime_v2 1.23.2+2 supplies Dart FFI bindings; all ONNX/sherpa native libraries are excluded from base Windows and Android packages. Explicit enhancement installation loads a shared verified native runtime from application support storage.
- SenseVoiceSmall: FunAudioLLM / Alibaba Group; int8 ONNX conversion by csukuangfj / sherpa-onnx. Conversion revision 2365baeacb507f821a0c8120fcee3d484dba7a07: https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17 . Its LICENSE refers to FunASR. Model weights have separate terms under the FunASR Model Open Source License Agreement, not the source toolkit's MIT license. Attribution and agreement v1.1 are retained in assets/licenses and the app license screen.
- PP-OCRv4: PaddleOCR / PaddlePaddle, converted to ONNX by RapidOCR / SWHL. Pinned model repository revision 1cfba2e90fc938db55889873735088de210cc173 declares Apache-2.0: https://huggingface.co/SWHL/RapidOCR . Full RapidOCR license and attribution are retained in assets/licenses.

Model weights and native inference libraries download only through the manual resource action, never during playback. Their exact lengths and SHA256 values are pinned in lib/media/content_filter/local_models.dart, keyword_models.dart and runtime_catalog.dart. The model-free visual/audio fingerprint code uses existing Dart image and numerical processing and does not load those libraries. These model terms remain separate from Zero Player's source license. The development speech fixture is locally synthesized by an installed Microsoft SAPI voice and is not bundled in the app or source archive.

## Xiaolai font

Xiaolai Regular v3.126 by LXGW, derived from SetoFont. Bundled under SIL Open Font License 1.1. Copyright and full license: assets/fonts/OFL.txt. Upstream: https://github.com/lxgw/kose-font .

## Noto Sans SC / Noto Serif SC

Bundled variable fonts from google/fonts (ofl/notosanssc and ofl/notoserifsc). SIL OFL 1.1; copyright and full notices in assets/fonts/NotoSans-OFL.txt and assets/fonts/NotoSerif-OFL.txt.

## MaccmsResources catalogs

assets/catalogs/maccms/Site.json and R18.json are snapshots from ZhaoYunxiong/MaccmsResources, commit e8ba0081d0ef7b4c6cc0c9c2a0de83226f0eb6db, fetched 2026-10-28. Copyright (c) 2022 ZYX, MIT; full notice in assets/catalogs/maccms/LICENSE. Upstream availability labels are not local probe results. Both categories retain their classification; new adult entries are disabled by default.

## Radio catalog source

popocoding/awesome-m3u provides radio/cn.m3u: https://github.com/popocoding/awesome-m3u . A successfully fetched and parsed catalog snapshot is bundled in assets/catalogs/radio/cn.snapshot.json, with its source and timestamp. Copyright (c) 2026 popocoding, MIT; full license in assets/catalogs/radio/LICENSE. tool/sync_radio_snapshot.dart refreshes this snapshot only after successful validation. No audio content is bundled. Catalog inclusion is not a certification of station availability or media rights. Radio is explicitly experimental.

## Branding

assets/brand/logo.jpg was supplied by the project owner. Platform icons and the Android TV banner are derived from that image using tool/generate_brand.py; it is not an upstream library asset.
