# 构建与打包

v0.0.2 本轮只验收 Windows x64。先执行 `flutter build windows --release --no-pub`，再执行 `pwsh -File tool/package_release.ps1 -WindowsOnly`。产物在 `artifacts/release/0.0.2/`；该模式不会把旧 Android 构建混入新版本。必须保留便携目录的 DLL、data 和第三方声明。

渠道核查使用 `flutter test tool/audit_sources.dart`；可用 `--dart-define=SOURCE_DATABASE=<路径>` 纳入本机渠道。对实际用户数据库应用快照前先用 `tool/backup_database.py` 创建一致性备份，再运行 `tool/apply_source_audit.dart`，显式提供 SOURCE_DATABASE 与 SOURCE_BACKUP。测试使用显式 `allowPrivateNetworks: true` 访问合成回环服务，生产入口不开放该权限。

工具链：Flutter 3.44.1 / Dart 3.12.1、JDK 21、Android SDK、Visual Studio 2022 C++ 桌面组件。pubspec.lock 锁定依赖。Android minSdk 26，支持 arm64-v8a 和 x86_64。

## 检查与开发

~~~powershell
flutter pub get
flutter analyze
dart run tool/check_source_size.dart
flutter test
pwsh -File tool/generate_fixtures.ps1 -FFmpeg <path-to-ffmpeg.exe>
flutter test integration_test/radio_flow_test.dart -d windows --no-pub
flutter test integration_test/radio_tray_test.dart -d windows --no-pub
flutter test integration_test/app_shell_regression_test.dart -d windows --no-pub
~~~

测试服务与媒体样本均由本地 fixture 提供。公开网络用例默认跳过，须显式选择。测试素材可用 FFmpeg 通过 generate_fixtures.ps1 重新生成，不提交大体积生成文件。Windows 平台测试与构建必须串行执行，测试后完整 release build 会刷新插件注册。

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

Windows 打包默认使用 .tools/inno/ISCC.exe，可通过 -Iscc 指定。-VcRuntime 指向本机 VS 可再分发运行库目录；安装器按用户安装无需管理员权限。便携版必须完整解压，不能只复制 EXE。

## 原生依赖与可追溯性

原生依赖通常由包构建脚本下载；网络需要时使用 tool/prefetch_native.ps1 与 tool/prefetch_dependencies.ps1。SQLite 摘要来自上游列表；media_kit MD5 来自锁定插件的构建脚本。不要将下载摘要当作独立代码签名。

原生组件的版本、上游源码与构建仓库见 NOTICE.md。collect_notices.py 收集 Dart 许可证与 FFmpegKit Windows 随附声明；发布附依赖声明和原生构建来源记录。它们不替代独立法律或供应链审计。

## 发布验证范围

Windows 原生测试覆盖首页、搜索、直播/播放、广播及全屏窗口恢复。Android 包须检查架构完整性与签名；未连接 Android 设备时不能宣称已完成实机/TV 验收。基础发布的测试范围和已知限制见 RELEASE-0.0.1.md。
