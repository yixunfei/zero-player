<p align="center"><img src="assets/brand/logo.jpg" alt="Zero Player" width="240"></p>

# Zero Player

面向 **Windows 桌面和 Android 手机 / TV** 的本地在线视频聚合播放器。支持频道浏览、聚合搜索、点播、直播、续播、离线下载与导出，无需单独部署业务后端。

**v0.7.2 预发行** · [下载 Windows 新版](https://github.com/yixunfei/zero-player/releases/tag/v0.7.2) · [Android v0.7.2 开发测试包](https://github.com/yixunfei/zero-player/releases/download/v0.7.2/zero-player-0.7.2-android-arm64-devtest.apk) · [Windows v0.0.11 稳定版](https://github.com/yixunfei/zero-player/releases/tag/v0.0.11) · [Android v0.0.7 正式版](https://github.com/yixunfei/zero-player/releases/tag/v0.0.7) · [使用指南](docs/implementation/USER-GUIDE.md) · [构建说明](docs/implementation/BUILD.md) · [版本说明](docs/implementation/RELEASE-0.7.2.md)

## v0.7.2

当前源码版本 **0.7.2+72**，包含网易云歌单补齐、全屏同步歌词和 Windows 在线音乐闪退的应用侧缓解。详见[版本说明](docs/implementation/RELEASE-0.7.2.md)。

## v0.0.14 源码版本

源码版本 **0.0.14+14** 新增在线同步歌词、风格歌单、队列预检及按延迟和音质选源。详见[版本说明](docs/implementation/RELEASE-0.0.14.md)。

## v0.0.13 预发行

源码版本 **0.0.13+13**：新增音乐随机播放结果、自动／手动换源、歌手与主题搜索，整合直连音乐渠道、同步歌词、歌单导入及发现页滚动稳定性修复。详见[版本说明](docs/implementation/RELEASE-0.0.13.md)。提供 Windows x64 安装器／便携包和 Android ARM64 开发测试包。下文 v0.0.12 段落保留历史说明。

## v0.0.12 预发行变更

该预发行版本为 **0.0.12+12**，修复原生警告误触发重播、异常清零后丢失进度、短资源续播归零、动态 HLS 旧缓存和旧媒体列表引用累积；纳入播放触摸、锁定与换集状态修复。新增手机横屏／自动旋转、软件解码恢复画面，以及重启后可导出的本机播放与内存诊断。沿用既有监管、内容过滤与网络访问策略。

本次为预发行，提供 Windows x64 和 Android ARM64 开发测试包。Android 名称「Zero Player 测试」，独立包名 `dev.zeroplayer.zero_player.devtest`，采用 Release 编译和已有本机测试签名，可覆盖同签名测试版并与正式版并存。原 Android 正式签名文件当前不可用，Android 最新正式版保持 v0.0.7。手机长时播放尚未验收；模拟器视频 EGL 与 Windows HLS 特征采样仍有未闭环项，不能宣称三个随机故障已全部消失。验收范围见[实施状态](docs/implementation/STATUS.md)。

全新安装提供可跳过的监管设置提示；首次在非监管状态关闭成人过滤需完成本机访问密码验证。新增默认关闭的“内容过滤设置需要监管验证”，修改该开关本身始终验证监管密码。监管开启期间仍禁止关闭成人过滤。已有安装升级免新增首次流程，普通备份不传递本机验证记录。详情见使用指南。

## 功能

- 影院与明亮主题，首页频道和搜索同栏展示，支持单类浏览、分类聚合、分页与继续观看。
- 可配置视频源与聚合搜索，标题纯文本清理、来源检查和失败提示。
- 点播、直播、播放快捷键、Windows 沉浸全屏和窗口恢复。
- 直播单击选中、双击播放，随包预检通过目录、更新复检后恢复，4/8/16 路测活、健康优先排序、同台别名合并、备用线路与可配置 XMLTV 节目表。 参见[内置直播源清单与维护](docs/implementation/LIVE_SOURCES.md)。
- 搜索默认查询全渠道，优先当前浏览来源；发现页推荐无当前来源，支持手动仅当前来源、失败重试与逐源进度。
- 统一成人过滤，监管模式覆盖点播、直播和广播；支持频道/关键词屏蔽，每次敏感操作验证密码，恢复码由用户自行保管。
- **在线广播（实验阶段）**：电台分组/搜索、收藏、广播与电视伴听分类、健康筛选/测活、失败换线、迷你播放器；离开页面继续播放，Windows 支持托盘收听与退出。
- **在线音乐**：默认浏览 QQ 音乐热歌，可选择网易云新歌和 Apple Music 中国区热门歌曲。Flutter 客户端直接请求各播放渠道，无需部署音乐服务器。首次搜索默认聚合 MY FREE MP3、网易云公开音频、Audius、酷狗公开音频和酷我试听，优先查询收藏渠道。可在“我的歌单”导入网易云公开歌单，在播放器查看网易云歌曲的同步歌词和可用译文。另有播放队列、历史续播、离线下载、迷你播放器和 Windows 托盘控制。渠道限制与实验性 LX 适配见[使用指南](docs/implementation/USER-GUIDE.md#在线音乐当前源码新增)。
- 渠道按实际诊断自动启停并持续复检，频道选择显示 TCP Ping；收藏和重复接口整理保持独立。
- 受控媒体网关、私网访问拦截、HLS 引用校验、原生脚本/协议限制与有界退出清理。
- 播放中特征跳过（默认关闭）：原画质直接播放，后台优先检测音频；没有规则、资源缺失或检测失败时继续播放。支持频道/全剧声画样本、保守/积极/提示策略、离线关键词检测。关键词始终先确认，默认跳过时长 20 秒，可调整并撤销。轻量关键词、OCR / ASR 资源在设置中手动下载，不随基础包安装。Android 实机性能待设备验收。详见 [实施记录](docs/implementation/VIDEO-CONTENT-FILTER-PLAN.md)。
- 下载、续传、指定目录自动保存、离线播放与 TS/MP4 导出；本地视频播放、续播、内嵌音轨/字幕选择及 Windows 可选文件关联（v0.0.8）。设置、历史记录及用户数据保存在本机。
- 一次性导航引导、版权说明与开源许可证入口。

广播内置源：[popocoding/awesome-m3u 的中国广播列表](https://raw.githubusercontent.com/popocoding/awesome-m3u/refs/heads/main/radio/cn.m3u)。首次离线可使用随包成功快照，超过 24 小时后台更新；刷新失败保留旧列表。源站可能变更，列表收录不保证可播放性或授权。

## 下载与安装

| 使用场景 | 发布文件 |
| --- | --- |
| Windows 10/11 x64 安装 | windows-x64-setup.exe |
| Windows x64 便携运行 | windows-x64-portable.zip（完整解压后运行 zero_player.exe） |
| Android 8.0+ ARM64 手机/平板/TV | v0.0.7 的 android-arm64.apk |
| Android 8.0+ ARM64 开发测试 | v0.0.12 的 android-arm64-devtest.apk（测试签名，独立包名） |
| 审查/重新构建 | source.zip、third-party-notices.zip 与原生构建来源材料 |

本次 v0.0.12 提供 `zero-player-0.0.12-windows-x64-setup.exe` 和 `zero-player-0.0.12-windows-x64-portable.zip`，另附源码、第三方声明、原生来源及 `SHA256SUMS.txt`。Android 开发测试附件为 `zero-player-0.0.12-android-arm64-devtest.apk`，附测试说明；最新正式 Android 包仍为 v0.0.7。Windows 二进制未做商业代码签名；本轮未重新验收安装卸载或 Android/TV 实机。

不支持 32 位 ARM/x86 Android、Windows ARM64 原生版、macOS 或 iOS。便携包必须完整解压，不能仅复制 EXE。

## 开发

当前实现、重装后的验证与待验收项统一见 [实施状态](docs/implementation/STATUS.md)；开发和原生测试命令见 [构建说明](docs/implementation/BUILD.md)。

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
| [iptv-org/iptv](https://github.com/iptv-org/iptv) | 中国公开直播列表来源 |
| [Xiaolai](https://github.com/lxgw/kose-font)、[Noto fonts](https://github.com/google/fonts) | 中文字体 |
| [Inno Setup](https://jrsoftware.org/isinfo.php)、[Pillow](https://github.com/python-pillow/Pillow) | Windows 安装器和品牌素材构建工具 |

各依赖保留其各自许可证，完整声明及原生组件来源见 [NOTICE.md](NOTICE.md)，发布包附第三方声明。不能将包含 mpv、FFmpeg 等组件的整个二进制包一概描述为 MIT。

## 版权与使用范围

本项目仅提供聚合和播放器入口，资源信息来自公开网络及用户配置的第三方渠道，不运营媒体源站。项目仅供学习交流；公开可访问不代表已获授权。媒体内容及相关商标的权利归各权利人，使用者应在合法授权范围内使用。若涉及内容版权问题，请联系对应渠道、内容提供方或列表维护方；项目自身代码问题可通过仓库 Issues 反馈。

应用不执行远程 Spider/JAR/JavaScript/Python，不绕过 DRM 或付费访问控制。默认无遥测和跨设备同步；联网加载频道、封面及播放资源会访问相关第三方服务。

项目代码采用 [AGPL-3.0-or-later](LICENSE)。测试通过不等于不存在所有缺陷；设备与源站差异仍可能影响体验。广播当前明确处于实验阶段。
