<p align="center"><img src="assets/brand/logo.jpg" alt="Zero Player" width="240"></p>

# Zero Player

面向 **Windows 桌面和 Android 手机 / TV** 的本地在线视频聚合播放器。支持频道浏览、聚合搜索、点播、直播、续播、离线下载与导出，无需单独部署业务后端。

**v0.0.4 Windows 监管模式构建** · [上一个公开版本 v0.0.1](https://github.com/yixunfei/zero-player/releases/tag/v0.0.1) · [使用指南](docs/implementation/USER-GUIDE.md) · [构建说明](docs/implementation/BUILD.md) · [本轮改进](docs/implementation/SUPERVISION-2026-10-28.md)

## 功能

- 影院与明亮主题，首页频道和搜索同栏展示，支持单类浏览、分类聚合、分页与继续观看。
- 可配置视频源与聚合搜索，标题纯文本清理、来源检查和失败提示。
- 点播、直播、播放快捷键、Windows 沉浸全屏和窗口恢复。
- 直播单击选中、双击播放，支持失败自动停用、未确定批量停用、停用项检测恢复及可验证元数据筛选。
- 搜索优先当前浏览来源，支持仅当前来源、失败重试与逐源进度。
- 统一成人过滤，监管模式覆盖点播、直播和广播；支持频道/关键词屏蔽，每次敏感操作验证密码，恢复码由用户自行保管。
- **在线广播（实验阶段）**：电台分组/搜索、收藏、广播与电视伴听分类、迷你播放器；离开页面继续播放，Windows 支持托盘收听与退出。
- 渠道按实际诊断自动启停并持续复检，频道选择显示 TCP Ping；收藏和重复接口整理保持独立。
- 受控媒体网关、私网访问拦截、HLS 引用校验、原生脚本/协议限制与有界退出清理。
- 下载、续传、离线播放与 TS/MP4 导出；设置、历史记录及用户数据保存在本机。
- 一次性导航引导、版权说明与开源许可证入口。

广播内置源：[popocoding/awesome-m3u 的中国广播列表](https://raw.githubusercontent.com/popocoding/awesome-m3u/refs/heads/main/radio/cn.m3u)。首次离线可使用随包成功快照，超过 24 小时后台更新；刷新失败保留旧列表。源站可能变更，列表收录不保证可播放性或授权。

## 下载与安装

| 使用场景 | 发布文件 |
| --- | --- |
| Windows 10/11 x64 安装 | windows-x64-setup.exe |
| Windows x64 便携运行 | windows-x64-portable.zip（完整解压后运行 zero_player.exe） |
| Android 8.0+ 手机/TV | android-arm64.apk；不确定架构时选 android-universal.apk |
| Android x64 设备/模拟器 | android-x64.apk |
| Android 分发工具输入 | android.aab（不能直接安装） |
| 审查/重新构建 | source.zip、third-party-notices.zip 与原生构建来源材料 |

上一个公开版本文件以 zero-player-0.0.1 开头；本轮 Windows 本地验收包以 zero-player-0.0.4 开头，未发布至 GitHub Releases。SHA256SUMS.txt 提供校验和。不支持 32 位 ARM/x86 Android、Windows ARM64 原生版、macOS 或 iOS。Android 使用独立项目签名；旧调试签名包不能直接覆盖安装。Windows 二进制未做商业代码签名。

## 开发

使用 Flutter 3.44.1 / Dart 3.12.1，锁定依赖见 pubspec.lock。Android 构建需要 JDK 21 和 Android SDK；Windows 构建需要 Visual Studio C++ 桌面工具链。

~~~powershell
flutter pub get
flutter analyze
dart run tool/check_source_size.dart
flutter test
~~~

lib/features 按业务划分；lib/media 包含播放、HLS、回环网关、缓存与导出；lib/core 提供网络、数据库和平台边界；lib/app 负责依赖组合、路由与布局。平台测试和 Flutter 构建应串行执行，避免共享插件注册文件冲突。图标由 assets/brand/logo.jpg 通过 tool/generate_brand.py 生成。

仓库仅提交代码、测试、必要素材、依赖锁文件和构建/使用说明。密钥、本地配置、下载工具链、测试产物、缓存和发行二进制均不进入 Git；发行文件通过 Releases 提供。

## 开源致谢

感谢以下项目及其贡献者。名称与链接用于注明来源，不表示上游为本项目或内置资源背书。

| 项目 | 在本项目中的用途 |
| --- | --- |
| [Flutter / Dart](https://github.com/flutter/flutter) | 跨平台应用框架与语言 |
| [LibreTV](https://github.com/LibreSpark/LibreTV) | 功能与公开接口协议参考；独立 Flutter/Dart 实现 |
| [media_kit](https://github.com/media-kit/media-kit)、[mpv](https://github.com/mpv-player/mpv) | 音视频播放及平台原生播放器 |
| [FFmpeg](https://ffmpeg.org/)、[FFmpegKit](https://github.com/sk3llo/ffmpeg_kit_flutter_android)、[Windows 移植](https://github.com/sk3llo/ffmpeg_kit_flutter) | 媒体处理、校验与导出 |
| [Riverpod](https://github.com/rrousselGit/riverpod)、[go_router](https://github.com/flutter/packages/tree/main/packages/go_router) | 状态管理与路由 |
| [Drift](https://github.com/simolus3/drift)、[sqlite3.dart](https://github.com/simolus3/sqlite3.dart)、[SQLite](https://sqlite.org/) | 本地数据持久化 |
| [window_manager](https://github.com/leanflutter/window_manager) | 桌面窗口控制 |
| [Dart html](https://github.com/dart-lang/tools/tree/main/pkgs/html)、[Dart XML](https://github.com/renggli/dart-xml) | HTML 与 XML 文档解析 |
| [Flutter packages](https://github.com/flutter/packages)、[Dart core](https://github.com/dart-lang/core) | 文件选择、存储路径、路径处理与摘要计算 |
| [awesome-m3u](https://github.com/popocoding/awesome-m3u) | 实验广播内置列表来源 |
| [Xiaolai](https://github.com/lxgw/kose-font)、[Noto fonts](https://github.com/google/fonts) | 中文字体 |
| [Inno Setup](https://jrsoftware.org/isinfo.php)、[Pillow](https://github.com/python-pillow/Pillow) | Windows 安装器和品牌素材构建工具 |

各依赖保留其各自许可证，完整声明及原生组件来源见 [NOTICE.md](NOTICE.md)，发布包附第三方声明。不能将包含 mpv、FFmpeg 等组件的整个二进制包一概描述为 MIT。

## 版权与使用范围

本项目仅提供聚合和播放器入口，资源信息来自公开网络及用户配置的第三方渠道，不运营媒体源站。项目仅供学习交流；公开可访问不代表已获授权。媒体内容及相关商标的权利归各权利人，使用者应在合法授权范围内使用。若涉及内容版权问题，请联系对应渠道、内容提供方或列表维护方；项目自身代码问题可通过仓库 Issues 反馈。

应用不执行远程 Spider/JAR/JavaScript/Python，不绕过 DRM 或付费访问控制。默认无遥测和跨设备同步；联网加载频道、封面及播放资源会访问相关第三方服务。

项目代码采用 [AGPL-3.0-or-later](LICENSE)。测试通过不等于不存在所有缺陷；设备与源站差异仍可能影响体验。广播当前明确处于实验阶段。
