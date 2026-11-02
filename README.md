<p align="center"><img src="assets/brand/logo.jpg" alt="Zero Player" width="240"></p>

# Zero Player

面向 **Windows 桌面和 Android 手机 / TV** 的本地在线视频聚合播放器。支持频道浏览、聚合搜索、点播、直播、续播、离线下载与导出，无需单独部署业务后端。

**v0.0.10 Windows x64** · [下载 Windows 新版](https://github.com/yixunfei/zero-player/releases/tag/v0.0.10) · [Android v0.0.7](https://github.com/yixunfei/zero-player/releases/tag/v0.0.7) · [使用指南](docs/implementation/USER-GUIDE.md) · [构建说明](docs/implementation/BUILD.md) · [版本说明](docs/implementation/RELEASE-0.0.10.md)

## v0.0.10 新增

当前版本为 **0.0.10+10**，新增在线音乐搜索、榜单与精选歌单、播放队列、历史续播和离线下载；支持多源并发搜索与本地下载优先显示。音乐与广播共享后台音频控制，并沿用既有监管、内容过滤与网络访问策略。

本次正式发行仅提供 Windows x64。原 Android 正式签名文件当前不可用，因此保留 Android v0.0.7，不用测试签名替换正式版。独立包名 `dev.zeroplayer.zero_player.devtest` 的 Android 测试构建不作为本次公开附件。验收范围见[实施状态](docs/implementation/STATUS.md)。

全新安装提供可跳过的监管设置提示；首次在非监管状态关闭成人过滤需完成本机访问密码验证。新增默认关闭的“内容过滤设置需要监管验证”，修改该开关本身始终验证监管密码。监管开启期间仍禁止关闭成人过滤。已有安装升级免新增首次流程，普通备份不传递本机验证记录。详情见使用指南。

## 功能

- 影院与明亮主题，首页频道和搜索同栏展示，支持单类浏览、分类聚合、分页与继续观看。
- 可配置视频源与聚合搜索，标题纯文本清理、来源检查和失败提示。
- 点播、直播、播放快捷键、Windows 沉浸全屏和窗口恢复。
- 直播单击选中、双击播放，随包预检通过目录、更新复检后恢复，4/8/16 路测活、健康优先排序、同台别名合并、备用线路与可配置 XMLTV 节目表。
- 搜索默认查询全渠道，优先当前浏览来源；发现页推荐无当前来源，支持手动仅当前来源、失败重试与逐源进度。
- 统一成人过滤，监管模式覆盖点播、直播和广播；支持频道/关键词屏蔽，每次敏感操作验证密码，恢复码由用户自行保管。
- **在线广播（实验阶段）**：电台分组/搜索、收藏、广播与电视伴听分类、健康筛选/测活、失败换线、迷你播放器；离开页面继续播放，Windows 支持托盘收听与退出。
- **在线音乐**：默认浏览网易云公开首页新歌推荐，点击后通过所选渠道搜索并记住本机渠道选择；复用视频封面组件和缓存，采用 Flutter 本机界面，无需部署音乐服务器。当前可选 [MY FREE MP3](https://myfreemp3.ink)、网易云公开音频、Audius、[无损音乐下载](https://flac.music.hi.cn/)匿名酷我试听及近期有原生播放验证记录的实验性 LX Hello World/HYW 分支；支持歌单、可整理的播放队列/下一首播放、四种播放模式、历史续播、离线下载、迷你播放器与托盘收听。[LX 仓库](https://github.com/pdone/lx-music-source)的 16 项与本地 v6 修复包仅列明适配状态和固定摘要，不执行脚本。具体能力和源站失败情况见实施状态。
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
| 审查/重新构建 | source.zip、third-party-notices.zip 与原生构建来源材料 |

本次 v0.0.10 提供 `zero-player-0.0.10-windows-x64-setup.exe` 和 `zero-player-0.0.10-windows-x64-portable.zip`，另附源码、第三方声明、原生来源及 `SHA256SUMS.txt`。Android 最新公开包仍为 v0.0.7。Windows 二进制未做商业代码签名；本轮未重新验收安装/卸载后的系统文件关联。

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
