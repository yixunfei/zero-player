# 实施状态与需求矩阵

更新：2026-10-30（Asia/Shanghai）。本文件是项目当前进度的唯一入口；下文日期章节和需求矩阵保留历史验收范围。

## 当前交接

- 当前源码版本为 `0.0.7+7`；v0.0.7 发布范围见 [版本说明](RELEASE-0.0.7.md)。首次安装与过滤授权、[渠道源安全加固](SOURCE-SECURITY-2026-10-29.md) 为后续源码更新。工作区已有未提交实现与测试，本轮保留，未提交或推送。
- 系统恢复后的项目根为 `K:/zero-player`。Flutter 3.44.1 / Dart 3.12.1、JDK 21、Android SDK、VS 2022 C++ 工具链可用。本机信息见 [.codex/LOCAL_ENVIRONMENT.md](../../.codex/LOCAL_ENVIRONMENT.md)。
- Android ARM64 debug APK 已在恢复阶段构建；本轮复核 SHA-256 与恢复记录一致：`f868082b7a3541a27077a4b8bac0d170c1c22642fb63487dd41858938f8b46e2`。此结论不代表 Release 或设备验收。
- 恢复阶段全量单元/组件回归：483 通过、2 项公网测试跳过；真实 RFC1918 网卡授权/撤销测试执行通过。日志 `build/restore-20261030-tests.log`。发布工具 Python 回归 6 项通过，源码规模检查通过。
- 修复 8 处原生测试旧盘符默认值，统一要求 `PROJECT_ROOT`；新增 `tool/run_windows_native.ps1` 自动传入当前路径、逐文件串行执行并隔离 TEMP/TMP，保留失败日志。
- 首次 Windows 原生回归发现 CMake 缓存绑定旧 L:；已将旧目录保留在 `build/windows-before-restore-20261030`，按原摘要校验复用 mpv/ANGLE 压缩包，重新生成 Windows 构建目录。原生复验 3 项通过：安全配置/受控播放 1 项，MP4/HLS 的 FFprobe 与 FFmpeg 声画采样 2 项（不将 tearDownAll 计入用例）。日志 `.dart_tool/native-8c0bcc01/`；驱动有既有插件检测提示，但实际取得成功结果且退出码为 0。
- 恢复阶段 `flutter analyze --no-pub` 无问题（`build/restore-20261030-final-analyze.log`）。
- Windows x64 普通 Release 重新构建通过（退出码 0），产物 `build/windows/x64/runner/Release/zero_player.exe`，必须保留同目录 DLL/data。日志 `build/restore-20261030-windows-release.log`；插件注册与产物检查确认无 integration_test 插件。本轮未生成安装器、公开发布或验收真实用户媒体。

## 搜索、线路与过滤增强（2026-10-30）

- 搜索新增高级匹配、排序、年份/地区/类型和排除词、分页预算；从渠道进入时默认限定该渠道。原有取消、增量展示、重试和监管策略保持。
- 详情默认先探测再选线，已知低清线路降级，未知画质明确展示；未确认可用的手动线路及实际播放选集探测失败时要求确认。手动选择不会被异步检测覆盖，探测请求沿用凭证作用域限制。
- 播放失败及重复预缓存失败可直接换线/换渠道；同集语义匹配、实际媒体探测后才自动换线，保留切换时刻的进度、暂停和倍速，避免按相邻索引盲切。跨渠道继续确认版本/剧集，预缓存失败退避且不打断已缓冲播放。
- 推广识别补充繁体/间隔符归一化、多命中区间合并、异常置信度处理；独立语音词表只含强特征，地名/“真人”等仍通过 OCR/完整语音上下文判断，避免误判和检测流重置造成的时间定位偏移。
- 全量单元/界面回归 492 通过、2 项公网测试跳过，日志 `build/search-playback-20261030-tests.log`。新增覆盖高级筛选、渠道限定、失败首线、低清降级、同集换线续播、预缓存失败退避和多区间识别。完整回归暴露既有授权界面测试固定等待 100 ms 的竞态，改为有界等待实际界面状态，保留全部授权断言；失败日志 `build/search-playback-20261030-tests-*-failure.log`。
- Windows 原生 6 项通过：后台 MP4/FLV/HLS 音频采样 3 项、真实播放关键词确认跳过/撤销 1 项、受控 MP4/HLS 采样 2 项。统一入口为 `./tool/run_windows_native.ps1 -TestFiles @('integration_test/background_filter_native_test.dart', 'integration_test/background_playback_controller_test.dart', 'integration_test/source_security_sampler_test.dart')`，成功日志 `.dart_tool/native-a5d668d2/`；此前失败证据保留，实际修复弱词过滤重置流的时间偏移后复验。
- `dart run tool/check_source_size.dart` 与 `flutter analyze --no-pub` 通过，普通 Windows x64 Release 构建通过（退出码 0）。日志 `build/search-playback-20261030-analyze.log`、`build/search-playback-20261030-release.log`；产物 `build/windows/x64/runner/Release/zero_player.exe`，须保留同目录 DLL/data。操作与边界见 [使用指南](USER-GUIDE.md) 新增章节。
- 尚未验证：真实用户媒体的全程可用性、实际画质与不良信息零漏检；Android/TV 实机。保留进度切换仍需要连接和解码，不承诺零间隙或跨版本时间轴完全一致。

## 广播与直播专项优化（2026-10-30）

- 测活默认 8 路、可选 4/8/16 路，同源最多 2 路；每路 128 KiB / 8 秒网络时间，优先上次成功地址并尝试全部备用线，可停止/重检。结果列表按需构建，避免数百/上千行同时布局。任意二进制响应不再直接通过：增加 TS / MP3 / AAC / FLV / MP4 / WAV / Ogg 等媒体特征检查，未知格式保留未确定；HLS 检测清单尾部媒体，网页与 JSON 不算媒体。
- M3U / TXT URL 支持内联请求头；M3U 增补 VLC Origin、EXTHTTP 和 Kodi HTTP 元数据解析，仅允许 HTTP 元数据，不执行原生插件或脚本。UA、公开 Referer / Origin 与来源凭证继续按既有网络边界处理，未放宽私网、重定向、监管和 DRM 限制。
- 频道按健康状态优先，保留同状态的央视自然排序；增加 `(SD)` / `[HD]` 等已知别名，保留体育赛事、区域、4K/8K 区别。广播同一订阅别名先合并所有备用 URL，再产生唯一 ID，避免重复 ID 导致检测丢线。
- 广播接入共享测活与健康持久化、状态筛选、健康排序和优选线路；原生错误/连接失败顺序换线，故障换线时丢弃旧引擎，快速换台和后台控制保持。停用项重新测活后按监管授权恢复，已移除项不参加。
- 节目表新增手机入口、加载/失败/空态、当前节目及进度、本地时间和主动刷新；关闭取消网络更新。支持编辑/清除订阅 XMLTV / XMLTV.GZ，清除选择跨订阅刷新及备份恢复保留。XMLTV display-name 用于无 tvg-id 的唯一匹配，显式 ID 支持无歧义大小写匹配，仍不猜测错配 ID。
- 新增 iptv-org 中国公开频道内置订阅；不批量替换或启用用户已停用的旧订阅。公网媒体抽样各取前 24 项：广播 19 响应 / 2 明确失败 / 3 未确定；fanmingming 综合 1 / 23 / 0，ITV 0 / 24 / 0；HerbertHe 国内 0 / 0 / 24；iptv-org 12 / 1 / 11；ssili126 列表当前仅 3 项，均未确定。证据 `build/live-radio-public-audit.json`、`build/live-radio-extra-audit.json`。多数旧直播头部确实返回 404，列表下载成功不能当作媒体可用。抽样只代表当前本机网络，不代表全量可用率或解码承诺。
- Windows 原生 2 项业务用例通过：新增真实 WAV / HLS 探测、UA / Referer 校验、原生错误自动换线及 HLS 实际伴听（`.dart_tool/native-ca950001/live_radio_media_test.log`）；既有广播导航、搜索、后台与迷你播放器（`.dart_tool/native-b2a69d23/radio_flow_test.log`）。驱动仍有既有 integration_test 插件提示，实际成功结果及退出码为 0；不把 tearDownAll 计入用例。
- Windows 普通 Release 构建通过，日志 `build/live-radio-windows-release-verified.log`，产物 `build/windows/x64/runner/Release/zero_player.exe`，必须保留同目录 DLL/data；已检查普通插件注册无 integration_test。初次构建未指定本地 FFmpegKit 而等待远程下载，已停止并按既有已校验本地包重跑，原日志保留。
- 最终全量单元/界面回归 503 通过、2 项按原配置跳过（build/live-radio-final-tests.log），flutter analyze --no-pub 无问题（build/live-radio-final-analyze.log），源码/函数规模检查及 git diff --check 通过。补充回归覆盖节目表清除后的备份恢复与广播别名多线路保留。Android/TV 实机、所有真实频道完整解码与长时间切台稳定性仍未验收；本轮未发布、未提交或推送，保留接手时工作区改动。

## 频道本机全量预检与内置可用表（2026-10-30 后续）

- 用户要求：完整本地遍历广播/直播，默认停用 404、不可用及尚未确认通过的频道；随包维护通过测试的目录，更新后复检通过才恢复。
- 已实现按频道 ID + URL/实际作用域请求头摘要索引证据，同一 ID 的旧缓存地址与新列表地址互不覆盖。内置证据只保存摘要和已通过线路序号，不发布本机完整流地址、令牌或请求头。直播随包列表快照与广播成功快照支持离线首次启动。
- 内置频道和更新后的新地址默认关闭至媒体响应检测通过。自动停用与用户停用分别记录：更新可恢复自动停用项，手动停用/已移除及监管限制保留；普通手动启用不能绕过预检。播放候选只使用已验证线路，未通过的原地址仍保留供后续复检。相同地址请求头变化也使证据失效。
- 列表刷新先提交待复检状态，再执行有界并发实际探测，取消或失败不会把未完成检测当成功；广播更新在发布新快照前复检。直播随包快照按原始更新时间保存，超过 24 小时可后台更新并验证。冷启动不会联网重新跑整份测试。
- 公开内置目录已完成 2,674 个频道 / 3,022 条去重线路的媒体探测，1,553 个频道有媒体响应；证据 build/channel-preflight-full.json。5 份列表当前无法下载，其已安装缓存另行纳入补测，不能把未能枚举的新列表称为已验证。
- 本机已安装应用的 2,860 条直播记录和 1 份广播快照（共 4,601 个频道条目）已完整补测：2,133 响应、635 明确失败、1,833 未确定。复用本轮 2,522 条完全相同 URL/作用域请求头的公开证据，其余逐一检查；同源 TCP/TLS 两次均无法连接时共享连接失败，并明确记为未确定而非 HTTP 404。未放宽本机网络权限。完整报告 build/local-channel-preflight-full.json；成功入口日志 build/local-channel-preflight-final-resumed.log，检查点和早期过程日志保留。
- 冻结合并 assets/live_channel_audit.json：4,965 条频道/请求记录，其中 2,241 通过、679 明确失败、2,045 未确定；仅通过项默认可用。公开直播快照位于 assets/catalogs/live/builtin.snapshots.json，广播快照更新到原位置。通过线路按首媒体响应优选，元数据取自同一条实际通过线路；合并节目也优先响应较快的来源。Python 冻结器拒绝不完整/矛盾或超过 24 小时的报告，原始本机流地址与请求头不进入可用表。
- 先在数据库副本验证应用，再对原库创建新一致性备份 build/preflight-user-before-apply-20261030.sqlite 并应用健康状态；本机当前 2,132 启用、2,469 停用，另 1 条虽有响应但原已停用而保留选择。旧版没有停用原因标记的记录保守保留，可用“检测并启用”恢复；新的自动停用状态支持更新复测通过后恢复。日志 build/channel-preflight-local-applied.log；18 张非健康表和其他 app_meta 数据均与备份完全一致，完整性检查 ok（build/channel-preflight-data-integrity.json）。未更改来源、收藏、账户、监管或网络授权。
- 最终全量单元/界面回归 510 通过、2 项按既有配置跳过（build/channel-preflight-final-tests.log）；Python 工具 11 项通过（build/channel-preflight-python-tests.log）；静态分析无问题，源码/函数规模检查、差异空白检查通过。早期在检测进程占用 SQLite DLL 时附加回归未能启动，失败证据保留；最终按检测结束后串行回归完成验收。
- Windows 原生 2 项业务用例通过：WAV/HLS 实际媒体、作用域 UA/Referer、失败换线、HLS 伴听，以及广播导航/搜索/后台/迷你控件；日志 .dart_tool/native-94e5d4a3/。驱动仍有既有插件提示，实际成功结果和退出码为 0，不把 tearDownAll 计入用例。
- 普通 Windows Release 构建通过（build/channel-preflight-windows-release.log），已核验随包预检表 SHA-256 与源码一致、普通插件注册无 integration_test（build/channel-preflight-release-check.json）。产物 build/windows/x64/runner/Release/zero_player.exe，须保留同目录 DLL/data。本轮未提交、推送或公开发布。Android/TV 实机和所有频道的完整解码、长期稳定性仍不在本机媒体响应预检结论内。

## 普通影片详情渠道/线路边界修复（2026-10-30）

- 用户确认问题位于普通影片详情页。本轮将渠道接口与片内媒体线路明确区分：选择渠道立即取消剩余接口检测；详情参数变化重新请求所选渠道/影片，清空旧详情、选线和播放确认状态，取消旧任务并隔离迟到结果。详情响应校验渠道和影片身份；线路探测只读取当前渠道返回的本片线路，显示渠道名和线路编号，不枚举其他渠道。
- 线路检测默认从 2 路提高到 8 路；渠道接口检测和搜索默认也为 8 路。设置分别提供「渠道接口检测并发数」和「片内线路检测并发数」1–16 路，保留已保存的个人配置。同源最多 2 路及播放优先预算保留，后台接口请求仍最多 4 路。
- 直播播放页的 CatalogItem.lines 代表频道，改为仅显示切台项，避免将整个频道列表当片内线路自动探测；批量可用性检测仍在直播页工具执行。本轮不重新修改已冻结预检表或本机频道健康数据库。
- 新增回归覆盖详情复用换渠道/影片、待返回详情取消、旧线路响应隔离、选定渠道后接口队列停止、3 路片内并发、8 路前台渠道 API 并发、直播切台无批量媒体请求、设置持久化与备份边界。全量单元/界面回归 517 通过、2 项按既有配置跳过（build/detail-line-full-tests.log）；静态分析无问题（build/detail-line-final-analyze.log），源码/函数规模及差异空白检查通过。早期新增测试的 ProviderScope/资源清理及代码风格失败日志保留，修正后完成全量复验。
- Windows 原生解析到实际播放回归 1 项通过（不将 tearDownAll 计入用例），日志 .dart_tool/native-2634a327/website_playback_test.log；驱动仍有既有插件提示，实际成功结果及退出码为 0。普通 Windows Release 构建通过（build/detail-line-windows-release.log），已核验插件注册无 integration_test、随包预检表与源码一致，产物检查见 build/detail-line-release-check.json。程序 build/windows/x64/runner/Release/zero_player.exe，须保留同目录 DLL/data；本轮未提交、推送或公开发布，Android/TV 设备尚未验收。

## 搜索默认范围与 0.0.8+8 真机测试交付（2026-10-30）

- 搜索进入时默认全渠道，当前来源仅作为请求及结果排序优先项，仍可手动切换「仅当前来源」。发现页推荐显式传递空来源，不继承旧详情上下文；详情打开期间保留当前来源，离开后恢复之前上下文。补充回归覆盖默认/手动范围、无来源入口及详情退出恢复，网络回归验证实际全渠道请求顺序。
- 版本更新为 0.0.8+8。全量单元/界面 518 通过、2 项按既有配置跳过（build/device-test-final-tests.log）；随后对最后的详情上下文恢复改动执行 7 项搜索/详情回归，全部通过（build/device-test-scope-regression.log）。Python 工具 12 项通过（build/device-test-python.log）。静态分析、源码/函数规模与差异空白检查通过；最后分析见 build/device-test-checked-analyze.log。一次临时诊断 Dart 文件触发 avoid_print，已移除后复验；失败日志保留。
- 普通 Windows x64 Release 构建通过（build/device-test-windows.log），EXE 内部版本为 0.0.8+8，普通插件注册无 integration_test。没有重跑此前已通过的真实媒体原生用例，本轮主要改动为搜索上下文及发行配置；前面章节的原生验证证据保持。
- 本机原正式 JKS 缺失，用户已确认独立 Android 测试包与正式版并存。Release 采用包名 dev.zeroplayer.zero_player.devtest、应用名「Zero Player 测试」和本机 Android debug 测试签名，独立数据目录；正常生产构建保留原签名校验。Windows Flutter/Dart 将环境变量名大写，首次混合大小写属性未生效并因缺少正式密钥失败；改为显式全大写 ZERO_PLAYER_DEVICE_TEST 属性后成功（build/device-test-android-arm64-verified.log）。构建环境变量在结束后恢复，未更改正式签名材料。
- ARM64 APK 64.83 MiB，内部版本、唯一 ARM64 ABI、必需原生库、三套字体、资源排除及 70 MiB 预算校验通过（build/device-test-apk-check.log）；APK v2 签名验证成功（build/device-test-apk-signature.log）。签名证书 SHA-256 为 d66972b598062015bc4092c1e45e05d8b4b437d6a1be8069e07907c1a97c14d6。
- 交付目录 artifacts/device-test/0.0.8-20261030-223707/：zero-player-0.0.8-windows-x64-setup.exe（67.47 MiB）、zero-player-0.0.8-windows-x64-portable.zip（88.36 MiB）、zero-player-0.0.8-android-arm64.apk（64.83 MiB），另含第三方声明、已校验原生依赖来源 ZIP、TEST-INFO.txt 和 SHA256SUMS.txt。Inno 编译通过（build/device-test-packaging.log），所有 ZIP CRC、SHA-256、便携包与 Windows 构建逐文件一致性、Windows/APK 预检表和直播/广播快照摘要均通过（build/device-test-package-check.json）。未将本机数据库或私钥打入交付包。
- 保留既有 v0.0.7 公开发布包。本轮是本地测试交付，未提交、推送或公开发布，也未改变 Git 暂存区。本机仅发现 x86_64 Android 模拟器，没有连接 ARM64 真机；本轮未实际安装 APK 或执行干净 Windows 安装。Android/TV 功能与长期播放仍需设备验收，测试签名包不能覆盖正式版。

## 下一步与验收边界

1. 持续使用 [构建说明](BUILD.md) 的统一原生入口，任何安全/媒体改动补做相关原生测试，再构建普通 Release，避免集成测试注册残留。
2. Android 手机/TV 的播放、后台行为、PiP、SAF、遥控器焦点及过滤性能仍需设备验收；当前没有连接 Android 设备，不以模拟器工具可启动替代产品验收。
3. 补齐两小时播放/切台压力、冷启动/首帧和资源曲线、干净 Windows 安装验证。公开发布前按当前签名及来源材料要求执行发布检查。

## 2026-10-28 阶段快照

渠道去重与清理、直播别名、广播快照及 Windows 托盘见 [当日报告](CHANNEL-RADIO-2026-10-28.md)。

用户已确认完整方案、回环网关、AGPL-3.0-or-later、合规复用。最新内置默认值按本地预检处理明确错误，保留既有手动选择；之前用户确认单会话五阶段增强、默认下载失败换源及显式多源分集并发。最新指示为先完成实现，模拟器/真机测试暂后。当前主应用已具备下列功能，不能据此把 M0–M6 的所有硬件和发布验收标为通过。

| 需求 | 实现位置与行为 | 验证状态 |
| --- | --- | --- |
| SRC-01–04 | sources：手动源、JSONC/LibreTV/受限 TVBox、noimank 多仓选择、#652 快照 | 解析测试通过；公网候选不保证可用 |
| SRC-05–07 | 探活取消、健康退避、订阅失败暂停/保留快照、共享归属与覆盖 | 网络/仓储测试通过 |
| SRC-08 | 来源文件导入导出、凭证排除、公开发布预览 | 文件路径已实现；未执行公网发布 |
| SEA-01–03 | 1–16 路可配置增量搜索、取消、聚合、历史、成人源/关键词过滤 | Windows 搜索流程及网络单测通过 |
| VOD-01–02 | 元数据占位、线路选集、续播与下载恢复重新解析 | Windows 详情/播放流程通过 |
| PLAY-01–04 | 原生播放、控制、自动连播、进度、语义换线/源 | Windows 解码/UI、播放会话单测通过 |
| PLAY-05–06 | 有界测速、声明/实际分辨率、3x长按、键盘/焦点 | 会话单测通过；遥控器/触摸实机待验 |
| PLAY-07–09 | 片段编辑/试跳/撤销/着色、保守广告过滤、有界恢复/取消 | 时间线及会话单测通过；更多真实流待验 |
| PLAY-10 | 截图保存、Android PiP、Windows 置顶小窗 | 平台代码已实现；设备能力待验 |
| LIVE-01–04 | M3U/请求头/备用线、HLS/FLV、EPG、收藏失效保留、测活/导出 | M3U/XMLTV 及回环模型测试通过；真实频道待验 |
| REC-01–03 | 豆瓣、Bangumi 按日、60s 豆瓣/百度榜单、缓存降级 | 确定性解析通过；公网曾返回 429，未认定 SLA |
| CACHE-01 | 前向预取、总量/单集预算、暂停行为、回退直通、持久索引 | 共享缓存/并发/租约测试通过；单集按分片粒度统计 |
| DOWN-01 | 排队、暂停/恢复、身份重新解析、HLS/MP4、离线能力 URL/哈希 | 离线与损坏拒绝测试通过；Android 前台下载待验 |
| DOWN-02 | 原生 FFmpeg 重封装、取消、完整解码验证、系统保存 | Windows 五类 HLS×MP4/TS 共10例通过；Android待验 |
| DATA-01–02 | SQLite、备份预览/语义验证/事务回滚、媒体与记录分开 | 数据库/备份单测通过 |
| UX-01 | 默认影院/柔和明亮/深色/系统主题、空态/错误/加载、手机底栏/桌面侧栏 | Windows 本机 UI 与390/1280布局通过 |
| TV-01–02 | Android TV入口、焦点控件、手动大屏、键盘返回/全屏 | 大屏截图已检查；真实TV全流程待验 |
| DIST-01 | APK、Windows release、Inno安装器、便携/源码、许可收集脚本 | 构建通过；正式签名/公开分发审计未完成 |

## 阶段结论

2026-10-28 已实现 MaccmsResources 双列表内置、点播与直播探活后的确认式清理、CCTV 别名归并、广播成功快照与订阅管理、收藏、离页播放、Windows 关窗驻留托盘。托盘原生集成使用回环 HTTP 静音音频验证隐藏后解码进度继续增长；Android 系统后台服务未包含。完整验证记录见本轮报告。

M1–M5 的主要产品能力已进入主应用；M0 媒体验证已有 Windows 证据。M6 已具备打包流程和开发交付物，但仍需 Android/TV 实机、干净 Windows 安装、两小时压力测试、冷启动/首帧/资源曲线与正式发布签名。不得把这些待验项目写成完成。

## 明确边界

- Android 包含 arm64/x64，最低 API26；Windows x64。未验证旧盒子/所有系统。
- Android 下载为前台任务，退后台暂停；不承诺后台服务下载。
- 广告过滤仅保守处理完整、未加密、单 TS 清单的成对 CUE 标记；主清单/独立音轨等回退原始。
- 单集播放缓存按资源粒度累计，存在在途分片超出软预算的边界；总缓存硬配额和下载配额独立。
- HLS 地址更新后完成任务会清理旧 pin；失败中间任务保留资源，删除任务释放。磁盘占用压力需长时验证。
- 源公开发布适配 HTTPS 纯文本 POST、响应纯文本 HTTPS URL 的服务，非通用粘贴板协议。
- Android SAF、PiP、真实TV焦点和公网推荐均不能用 Windows 结果替代。
- 开发 APK 使用 debug key，Windows 未代码签名。原生 mpv/FFmpeg/ANGLE 的完整对应源码分发审计待正式发布前完成。

证据见 [测试报告](TEST-REPORT.md)，操作见 [使用指南](USER-GUIDE.md)。

## 2026-10-27 体验增强

已实现：影视推荐主页、主推海报与继续观看、源真实分类、应用 F11 全屏；内置 CMS 默认启用、批量启停/移除/恢复、播放时屏蔽源；后台有界检测、延迟和主站元信息；可配置搜索并发、跨源同作品合并；优先级网络预算、取消及有界重试；详情批量选集下载、整集失败换源、显式多源分集并发；播放覆盖控件自动隐藏、防误触、手势和真实 HLS 画质选择。

数据库只增加本轮所需字段，打开现有 v1 数据库时执行一次增量升级以保留记录。不是通用历史格式兼容框架。

具体默认值、操作和保守匹配条件见 USER-GUIDE.md，最新测试结果见 TEST-REPORT.md 的体验增强部分。TVBox 多仓与 Spider 不被视为已可用的内置 CMS；公网可用率、Android 后台服务和硬件真机测试未承诺。

## 2026-10-27 首页专项修复

已复现默认豆瓣封面请求头触发 CDN 403/418，修复图片加载链路并校验返回内容。新增明确的推荐提供方标识、持久默认开屏频道和布局、单频道真实分类聚合、自动分页/下拉刷新、请求取消与去重、列表和图片缓存上限。实现与预算详见 [首页专项记录](HOME-ENHANCEMENT.md)，验证以 TEST-REPORT.md 最新章节为准。


## 2026-10-27 本轮交互与直播

完成四种字体选择、可配置手动加载数量、导航和搜索对比度、搜索退出与系统返回、Home/End/PageUp/PageDown、默认开屏全屏开关、电视式直播浏览、央视默认选中但不自动播放、频道及订阅持久启停与检测。补入用户列出的三个直播项目，使用真实解析器检查 76 个点播入口和 11 份直播列表。详情及最新验证见 INTERACTION-LIVE-2026-10-27.md 和 TEST-REPORT.md。
