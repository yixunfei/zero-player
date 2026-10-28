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
