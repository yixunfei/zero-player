# 构建与打包

## 首次使用与过滤授权回归

新增 `integration_test/installation_access_test.dart`，Windows 原生覆盖首次监管设置、隐藏密码错误与成功、取消、重启持久化、监管期间成人过滤锁定，以及恢复备份的双重验证。测试通过 `ADULT_ACCESS_TEST_PASSWORD` 编译参数读取由维护者提供的访问密码，未提供时仅运行不需要该密码的用例；不要把真实值提交到源码、日志或截图。建议用忽略目录下的临时 JSON 配合 `--dart-define-from-file`，完成后删除。

本轮静态分析与源码长度检查通过；单元及界面回归 466 项通过、2 项公开网络测试跳过。新增原生用例 3 项、既有监管原生用例 1 项、窗口原生用例 2 项均通过。Windows Release 与 Android ARM64 Release 构建通过，APK 为 64.48 MiB，通过 ABI、可选资源排除、70 MiB 预算及 v2 签名校验。Android 未连接设备，编译与包体校验不能替代实机运行验收。发布的 v0.0.7 产物保持原样，本轮补充功能在新版本正式发布前仅属于源码更新。

## v0.0.7 发布配置

本版本为 `0.0.7+7`，发布 Windows x64 与 Android ARM64。完成测试后依次执行 `flutter build windows --release`、`flutter build apk --release --target-platform android-arm64`；平台构建不可并发。随后校验 Android 签名，执行 `python tool/collect_native_sources.py`、`python tool/collect_notices.py`，暂存审查后的源文件并运行 `python tool/package_source.py`，最后 `pwsh -File tool/package_release.ps1 -AndroidArm64Only`。产物位于 `artifacts/release/0.0.7/`。此模式校验 ARM64、70 MiB 预算及 APK 内部版本，不混入其他旧 Android 包。

原生测试每个文件使用独立短临时目录，例如 `.dart_tool/native-007/<随机ID>`；应从固定根目录创建，不能连续使用修改后的 TEMP 作为下一层父目录，避免 Windows 路径过长。新增 `probe_modalities_test.dart` 验证缺失音轨/画轨时保留可用模态。`tool/check_keyword_native.dart` 验证连续、重叠切片及 reset 后重播。

版本展示由 `lib/app/app_version.dart` 统一，`test/data/app_version_test.dart` 保证其与 pubspec.yaml 相同。Python 发布工具回归执行 `python -m unittest discover -s tool -p 'test_*.py' -v`。下文 v0.0.6 和早期构建记录保留作历史参考；当前验收以 [v0.0.7 说明](RELEASE-0.0.7.md) 为准。

## 内容特征复用回归（2026-10-29）

本轮新增 `integration_test/feature_reuse_native_test.dart`，覆盖跨集 3137ms 内容偏移、提示确认/撤销、重新提取保留 ID 与启用状态。与 `audio_feature_playback_test.dart`、`discontinuous_playback_test.dart` 分别单独运行，每个文件使用新的 TEMP/TMP；不要在同一次 Windows `flutter test` 命令中传入多个集成文件。设置 FFMPEGKIT_LOCAL_DIR 的方法见下文。

验证记录：419 项单元/组件测试通过、2 项按原配置跳过，Windows 原生 5 项通过，静态检查和源码规模检查通过，Windows Release 构建成功。设计与基础能力边界见 `FEATURE-REUSE-20261029.md`。

v0.0.6 本轮只验收 Windows x64。先执行 `flutter build windows --release --no-pub`，核验原生来源及许可证，暂存经审查的源码并运行 `python tool/package_source.py`，再执行 `pwsh -File tool/package_release.ps1 -WindowsOnly`。产物在 `artifacts/release/0.0.6/`；该模式不会把旧 Android 构建混入新版本。必须保留便携目录的 DLL、data 和第三方声明。打包前验证 Windows 二进制完整版本号与 pubspec.yaml 一致，拒绝复用已有 staging。

渠道核查使用 `flutter test tool/audit_sources.dart`；可用 `--dart-define=SOURCE_DATABASE=<路径>` 纳入本机渠道。对实际用户数据库应用快照前先用 `tool/backup_database.py` 创建一致性备份，再运行 `tool/apply_source_audit.dart`，显式提供 SOURCE_DATABASE 与 SOURCE_BACKUP。测试使用显式 `allowPrivateNetworks: true` 访问合成回环服务，生产入口不开放该权限。

工具链：Flutter 3.44.1 / Dart 3.12.1、JDK 21、Android SDK、Visual Studio 2022 C++ 桌面组件。pubspec.lock 锁定依赖。Android minSdk 26，支持 arm64-v8a 和 x86_64。

## 检查与开发

~~~powershell
flutter pub get
flutter analyze
dart run tool/check_source_size.dart
flutter test
python -m unittest discover -s tool -p test_package_source.py -v
pwsh -File tool/generate_fixtures.ps1 -FFmpeg <path-to-ffmpeg.exe>
flutter test integration_test/radio_flow_test.dart -d windows --no-pub
flutter test integration_test/radio_tray_test.dart -d windows --no-pub
flutter test integration_test/app_shell_regression_test.dart -d windows --no-pub
~~~

测试服务与媒体样本均由本地 fixture 提供。公开网络用例默认跳过，须显式选择。测试素材可用 FFmpeg 通过 generate_fixtures.ps1 重新生成，不提交大体积生成文件。Windows 平台测试与构建必须串行执行，测试后完整 release build 会刷新插件注册。

## 干净 Windows 构建与原生测试

清理生成缓存使用 Flutter 标准命令 flutter clean；不会删除 artifacts 中的旧发行包与用户备份。清理后先 flutter pub get，再按需运行预置脚本；Windows SQLite DLL 与 Android 库均按锁定版本摘要校验。

~~~powershell
pwsh -File tool/prefetch_dependencies.ps1
pwsh -File tool/prefetch_native.ps1 -Platform windows
$env:FFMPEGKIT_LOCAL_DIR = (Resolve-Path .tools/ffmpegkit/unpacked).Path
# 每轮原生回归使用新的临时目录，避免 media_kit 调试引用文件遇到 PID 重用。
$testTemp = Join-Path ([IO.Path]::GetTempPath()) ('zero-player-native-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testTemp | Out-Null
$env:TEMP = $testTemp
$env:TMP = $testTemp
flutter test integration_test/supervision_flow_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
~~~

PROJECT_ROOT 应替换为实际仓库路径。监管用例仅写临时数据库，真实用户库不会写入测试密码；恢复码不输出到日志或截图。Release 不使用 media_kit 的调试指针持久化逻辑。

## 内容过滤原生回归

本功能默认关闭；基础声画指纹无需模型或额外推理库。增强 OCR/ASR 只允许设置页手动安装。开发验收使用项目合成的广告文字、正常画面和 Windows 中文 SAPI 口播，不使用真实业务媒体，也不将其视为真实源准确率测试。测试中的回环网络权限不进入生产设置。

~~~powershell
# 安装 Pillow，提供包含 libx264 的本机 FFmpeg 可执行文件。
pwsh -File tool/generate_filter_speech.ps1
python tool/generate_content_filter_fixtures.py --ffmpeg <path-to-ffmpeg.exe>
dart run tool/prepare_content_filter_runtime.dart
dart run tool/prepare_content_filter_models.dart test_support/generated/content_filter/models
dart run tool/fixture_server.dart
~~~

保持 fixture 服务运行；另一个终端按上文 Windows 临时目录约定设置 TEMP/TMP 和 FFMPEGKIT_LOCAL_DIR，然后执行：

~~~powershell
flutter test integration_test/content_filter_native_test.dart -d windows --no-pub --dart-define=FILTER_RUNTIME="$((Resolve-Path .tools/content-filter/runtime).Path)"
~~~

Android 先使用 JDK 21，必要时执行 prefetch_native.ps1 -Platform android 和 prefetch_dependencies.ps1；Flutter 构建与平台测试串行。调试包构建：

~~~powershell
flutter build apk --debug --no-pub --target-platform android-arm64,android-x64
python tool/verify_apk.py build/app/outputs/flutter-apk/app-debug.apk --debug
# 连接并授权 USB 调试设备后，用 adb devices 查找序列号。
adb -s <device-id> reverse tcp:9763 tcp:9763
flutter test integration_test/content_filter_native_test.dart -d <device-id> --no-pub
adb -s <device-id> reverse --remove tcp:9763
~~~

Android 构建成功只证明编译与打包；HLS、MP4、FLV 的真实设备播放、模型加载及性能须以原生回归结果验收。详细状态记录在 VIDEO-CONTENT-FILTER-PLAN.md。OCR 的 onnxruntime_v2 FFI 与 sherpa 共用 sherpa 的原生 ONNX Runtime；基础包排除全部 ORT/sherpa 原生库，不能重新加入 Maven/DLL；运行时通过校验过的应用数据目录加载。verify_apk.py 同时检查可选库和模型未进入包体。模型归属、协议和校验值随源码保留，collect_notices.py 会收集 assets/licenses。

## 手机 ARM64 小体积构建

保留三套字体，以 JDK 21 构建单 ABI Release；双 ABI 通用包包含额外原生库，不能用来衡量手机专用包。以下脚本构建后检查 arm64 原生库完整性、三套字体、原生库 ZIP 压缩、可选模型/推理库缺席及 70 MiB 预算，生成 APK 与 SHA256SUMS.txt。需要已有 android/key.properties；不自动创建或更换签名。

~~~powershell
pwsh -File tool/build_phone.ps1
# 已完成同源码的 arm64 Release 构建时可仅校验和复制：
pwsh -File tool/build_phone.ps1 -SkipBuild
~~~

产物：artifacts/phone/zero-player-android-arm64.apk。脚本拒绝覆盖内容不同的已有产物；新一轮用 -OutputDirectory 指定其他目录。APK 中保留原有字体选项。不要将已下载的测试模型打入 assets。Flutter 平台测试全部结束后再构建 Release，保留 pub 刷新插件注册的步骤，避免残留 integration_test 插件进入普通构建。

手机 APK 使用 jniLibs.useLegacyPackaging 压缩原生库；Android 安装时将库解压。该优化减少下载/安装包大小，不承诺同等降低安装后的占用。2026-10-29 同为 ARM64 Release 的旧包为 91.89 MiB，新包约 64.4 MiB；最终精确字节数和摘要随本地构建记录保存。

### 时间轴与特征标记回归

以下用例自建回环服务和临时数据库；使用现有合成 HLS 分片，故意将四段 TS 时钟各自归零，验证原生播放连续、用户特征命中、撤销后重播再次命中及原生截图。按前文设置全新的 TEMP/TMP 与 FFMPEGKIT_LOCAL_DIR 后执行：

~~~powershell
flutter test integration_test/discontinuous_playback_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
flutter test integration_test/audio_feature_playback_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
~~~

过滤开启时，网关对完整点播清单的分片进行 TS 字节校验，不依赖 .ts 后缀或 discontinuity 标签。仍不处理直播、加密、fMP4、字节区间或重复 URI 清单；无效、加密或超大 TS 返回原始内容。时间戳变化本身不用于判定广告，跳过仍需要特征、用户明确标记区间或显式清单标记。首次保存特征并开启过滤时，播放器保留位置、倍速和暂停状态重新打开媒体，使新时间轴立即生效。第二个原生用例验证默认音频模式、包含停顿的口播、跨影片特征匹配、非整秒 seek、撤销和再次命中。

### 后台过滤回归

~~~powershell
# 使用与设置页相同的下载、校验、解包链路，仅开发手动运行。
dart run tool/prepare_keyword_models.dart
dart run tool/check_keyword_native.dart
# 保持 fixture_server 运行，并按上文设置全新 TEMP/TMP 和 FFMPEGKIT_LOCAL_DIR。
flutter test integration_test/background_filter_native_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
flutter test integration_test/background_playback_controller_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
~~~

原生测试模型固定放在 .tools/content-filter/kws-source/ 对应版本目录，运行库在 .tools/content-filter/runtime/；模型目录也可使用 prepare_keyword_models.dart 的位置参数指定。前一组验证 MP4/FLV/HLS 原流播放中的后台识别和恢复，后一组验证真实 PlaybackController 自动跳过及撤销。Windows 的结果不能代替 Android 模型加载与流畅度验收。

## Android 签名

首次自行发行可执行 python tool/setup_android_signing.py --create。脚本在用户主目录 .zero-player/signing 中创建私有 JKS 和恢复配置，生成被 Git 忽略的 android/key.properties。后续必须复用同一签名，不要重复生成；请自行安全备份此目录。缺失配置时 release 打包会显式失败，不回退到调试签名。

若已有签名，直接创建本地 android/key.properties，填写 storeFile、storePassword、keyAlias、keyPassword，绝不能提交私钥或此文件。公开仓库无需也不包含发布密钥。旧 debug 签名安装与正式签名不同，迁移前应先导出本地设置/历史备份。

## 生成平台产物

~~~powershell
flutter build apk --release --target-platform android-arm64,android-x64
flutter build apk --release --target-platform android-arm64,android-x64 --split-per-abi
flutter build appbundle --release --target-platform android-arm64,android-x64
flutter build windows --release
python tool/collect_native_sources.py
python tool/collect_notices.py
# 先审查并暂存需要发行的源文件，源码 ZIP 严格跟随 Git index。
git add .
python tool/package_source.py
pwsh -File tool/package_release.ps1
~~~

产物位于 artifacts/release/<version>/。包括通用及分架构 APK、AAB、Windows x64 安装器/便携 ZIP、源码 ZIP、第三方声明和 SHA256SUMS.txt。AAB 是分发输入，不能直接安装；安装器未做商业 Authenticode 签名。打包脚本拒绝覆盖已有 Windows staging，请检查旧目录后换用新的干净 staging。

源码 ZIP 从一次固定的 Git index tree 读取版本与文件 blob，保留暂存内容的精确字节。未暂存的修改、工作区删除或本地换行转换不会改变归档；修改发行源码后须重新暂存并重新生成源码 ZIP 与 SHA256SUMS.txt。

Windows 打包默认使用 .tools/inno/ISCC.exe，可通过 -Iscc 指定。-VcRuntime 指向本机 VS 可再分发运行库目录；安装器按用户安装无需管理员权限。便携版必须完整解压，不能只复制 EXE。

## 原生依赖与可追溯性

原生依赖通常由包构建脚本下载；网络需要时使用 tool/prefetch_native.ps1 与 tool/prefetch_dependencies.ps1。SQLite 摘要来自上游列表；media_kit MD5 来自锁定插件的构建脚本。不要将下载摘要当作独立代码签名。

原生组件的版本、上游源码与构建仓库见 NOTICE.md。collect_notices.py 收集 Dart 许可证与 FFmpegKit Windows 随附声明；发布附依赖声明和原生构建来源记录。它们不替代独立法律或供应链审计。

## 发布验证范围

Windows 原生测试覆盖首页、搜索、直播/播放、广播及全屏窗口恢复。Android 包须检查架构完整性与签名；未连接 Android 设备时不能宣称已完成实机/TV 验收。基础发布的测试范围和已知限制见 RELEASE-0.0.1.md。

### 标记恢复回归（2026-10-29）

使用本机合成的 content_filter 素材。每次 Windows 原生测试使用全新 TEMP/TMP，并设置 FFMPEGKIT_LOCAL_DIR；三个文件顺序运行，不能与 release 构建并发：

~~~powershell
flutter test integration_test/feature_capture_recovery_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
flutter test integration_test/audio_feature_playback_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
flutter test integration_test/discontinuous_playback_test.dart -d windows --no-pub --dart-define=PROJECT_ROOT=L:/zero-player
~~~

feature_capture_recovery 在临时目录生成静音、无音轨、短音轨和 355 秒口播素材，测试结束清理。原生测试完成后再执行 flutter build windows --release（含依赖解析），确保发布目录不带 integration_test 插件。历史交付目录 artifacts/local/20261029-mark-repair 对应旧构建标识 mark-repair-20261029。

### 完整片段与跨集修复（feature-boundaries-20261029）

新增原生回归 `feature_long_segment_native_test.dart` 覆盖 16 秒完整片段、3.137 秒偏移、AAC 44.1 kHz 双声道重编码、全剧和频道复用。继续运行 `feature_reuse_native_test.dart`、`feature_capture_recovery_test.dart`、`discontinuous_playback_test.dart`，每个文件单独设置新的 TEMP/TMP，顺序执行。

本轮直接构建 `build/windows/x64/runner/Release/zero_player.exe`，与同目录 DLL、data 一起使用。不要从历史 artifacts/local 目录启动旧程序。实现与验证说明见 [完整片段修复记录](FEATURE-BOUNDARIES-20261029.md)。

### 续播同步与管理授权（feature-seek-sync-20261029）

新增 `integration_test/feature_seek_resume_native_test.dart`：真实 MediaKit + AAC 素材验证下一集 310.5 秒续播、重复观看、暂停拖动、连续跳转和频道其他作品复用。与长片段、特征复用和不连续时间轴原生测试按顺序执行，每个文件使用独立 TEMP/TMP。

当前运行的旧 Release 进程仍占用原目录，修复版使用进程专用 APPDATA 配置，将 Flutter 构建目录指向 `build/feature-seek-sync`，不会修改用户的全局 Flutter 设置。交付目录为 `artifacts/local/20261029-feature-seek-sync`，启动其中的 `zero_player.exe`；保留同目录 DLL 和 data。构建标识、测试结果与 app.so SHA256 写入 `BUILD-INFO.json`。
