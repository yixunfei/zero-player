# Zero Player v0.0.11

- 发现音乐默认使用 QQ 音乐热歌，可选择网易云新歌或 Apple Music 中国区热门歌曲，并记住本机选择。发现数据与播放渠道独立，点击歌曲后仍通过所选渠道搜索。
- 优先显示缓存；慢请求最多等待 6 秒，首次联网失败也可浏览本地编辑精选。网易云和 Apple Music 封面使用缩略图，减少图片传输与滚动开销。
- 音乐渠道可收藏，MY FREE MP3 默认收藏；收藏渠道在选择列表中靠前，聚合搜索优先调度，取消收藏后重启保留。
- 精修手机竖横屏、平板、桌面和 TV 尺寸下的交互：音乐导航横向滚动，推荐网格适配字体，广播工具栏与列表整体滚动，小窗口使用精简播放条，共用空状态支持滚动。
- 纳入已复核的播放器收尾、跳转错误提示、直播导出授权、广播重连、下载保存与解析健壮性修复；保留监管、内容过滤与网络访问边界。

正式发行仅包含 Windows x64 安装器、便携包、源码、第三方声明及原生来源。Android 正式签名仍缺失，最新 Android 正式版保持 v0.0.7。

验证：全量回归 639 项通过、8 项公网用例按配置跳过；Python 工具回归 14 项通过，静态分析和源码规模检查通过。五种尺寸（320×640、568×320、768×1024、1280×720、1920×1080）和 1.6 倍文字下检查九个主页面。三家推荐接口分别取得 30/10/50 首歌曲；Windows 原生受控播放、离线音乐、发现到 MY FREE MP3 搜索及实际解码三项业务通过。普通 Windows Release 构建通过，详细证据见 STATUS.md。

本轮审阅当前差异与关键交互/生命周期路径，历史 123 项审查仍有未闭环条目，不代表已消除全部潜在问题。Android/TV 实机、安装卸载、真实媒体长时播放和各用户网络表现未验收。公开音乐服务的可用性取决于源站。

## Android 开发测试包（2026-11-06 补充）

按用户要求补充 [Android ARM64 开发测试 APK](https://github.com/yixunfei/zero-player/releases/download/v0.0.11/zero-player-0.0.11-android-arm64-devtest.apk)（65.00 MiB，Android 8.0+）。版本为 `0.0.11+11`，应用名称「Zero Player 测试」，独立包名 `dev.zeroplayer.zero_player.devtest`；采用 Release 编译与已有本机测试签名，可与正式版并存、数据隔离。

包体、版本/包名、ARM64 原生库、三套字体、可选推理资源未入包、ZIP CRC 及 v2 签名校验通过；签名证书与 v0.0.9 开发测试包一致，可用于同签名开发版升级。业务源码与 v0.0.11 发行提交 `fe5aae8` 一致。未连接 Android 设备，尚未进行安装与实机播放验收。

另附 [Android 测试包校验清单](https://github.com/yixunfei/zero-player/releases/download/v0.0.11/zero-player-0.0.11-android-devtest-SHA256SUMS.txt) 和 [测试说明](https://github.com/yixunfei/zero-player/releases/download/v0.0.11/zero-player-0.0.11-android-devtest-INFO.txt)。原六个发行附件及其摘要保留；Android 最新正式版仍为 v0.0.7，此 APK 作为独立开发测试版提供。
