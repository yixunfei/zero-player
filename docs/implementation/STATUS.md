# 实施状态与需求矩阵

更新：2026-11-02（Asia/Shanghai）。本文件是项目当前进度的唯一入口；下文日期章节和需求矩阵保留历史验收范围。

## v0.0.10 审阅与发行（2026-11-02）

- 纳入已有音乐渠道和网络边界加固改动；补充修复推荐歌手/专辑及试听格式异常类型处理，避免远端畸形可选字段使正常歌曲不可用。
- 版本 0.0.10+10，Windows x64 正式发布；Android 保持既有正式签名边界，不发布测试签名升级包。
- 全量回归 616 通过、5 跳过；Python 工具回归 12 通过，源码规模检查通过。新增回归、静态分析与构建日志为 build/review-targeted.log、build/review-analyze-final.log、build/review-windows.log。
- 未验收 Android/TV 实机、安装卸载、真实媒体长时播放；不宣称本轮消除所有潜在缺陷。

## 当前交接（发行前历史快照）

- 在线音乐发现页默认改为网易云无需登录的首页新歌公开推荐，只取标题、歌手、封面等搜索元数据；播放仍经所选渠道搜索。失效渠道复核与未接入候选见下节；当前改动尚未进入安装包。

- 当前源码新增恶意渠道与跨站攻击增量防护（见下节）；现有安装包未包含这些更改。

- 当前源码版本 `0.0.9+9`，本轮纳入多源并发搜索、本地下载优先显示及分类精选歌单，详情见“音乐聚合搜索与分类优化”和 [v0.0.9 版本说明](RELEASE-0.0.9.md)。
- 在线音乐、歌单、播放模式、历史续播、离线下载、推荐封面及更多原生渠道的核查见“在线音乐核查与修复”；v0.0.8 已发行附件不包含音乐功能。
- 最新本地测试包：`artifacts/device-test/0.0.9-20261101-083645/`，包含 Windows 安装器/便携包及独立包名 Android ARM64 测试签名 Release；旧包保留。
- 本轮 `0.0.9+9` 正式发行范围为 Windows x64；Android 最新正式公开包仍为 v0.0.7。v0.0.8 仅发行 Windows x64，说明见 [版本说明](RELEASE-0.0.8.md)。v0.0.7 发布范围见 [版本说明](RELEASE-0.0.7.md)。首次安装与过滤授权、[渠道源安全加固](SOURCE-SECURITY-2026-10-29.md) 等后续源码更新已于 2026-10-31 作为提交 `acb4d81` 推送至 `origin/main`。
- 系统恢复后的项目根为 `K:/zero-player`。Flutter 3.44.1 / Dart 3.12.1、JDK 21、Android SDK、VS 2022 C++ 工具链可用。本机信息见 [.codex/LOCAL_ENVIRONMENT.md](../../.codex/LOCAL_ENVIRONMENT.md)。
- Android ARM64 debug APK 已在恢复阶段构建；本轮复核 SHA-256 与恢复记录一致：`f868082b7a3541a27077a4b8bac0d170c1c22642fb63487dd41858938f8b46e2`。此结论不代表 Release 或设备验收。
- 恢复阶段全量单元/组件回归：483 通过、2 项公网测试跳过；真实 RFC1918 网卡授权/撤销测试执行通过。日志 `build/restore-20261030-tests.log`。发布工具 Python 回归 6 项通过，源码规模检查通过。
- 修复 8 处原生测试旧盘符默认值，统一要求 `PROJECT_ROOT`；新增 `tool/run_windows_native.ps1` 自动传入当前路径、逐文件串行执行并隔离 TEMP/TMP，保留失败日志。
- 首次 Windows 原生回归发现 CMake 缓存绑定旧 L:；已将旧目录保留在 `build/windows-before-restore-20261030`，按原摘要校验复用 mpv/ANGLE 压缩包，重新生成 Windows 构建目录。原生复验 3 项通过：安全配置/受控播放 1 项，MP4/HLS 的 FFprobe 与 FFmpeg 声画采样 2 项（不将 tearDownAll 计入用例）。日志 `.dart_tool/native-8c0bcc01/`；驱动有既有插件检测提示，但实际取得成功结果且退出码为 0。
- 恢复阶段 `flutter analyze --no-pub` 无问题（`build/restore-20261030-final-analyze.log`）。
- Windows x64 普通 Release 重新构建通过（退出码 0），产物 `build/windows/x64/runner/Release/zero_player.exe`，必须保留同目录 DLL/data。日志 `build/restore-20261030-windows-release.log`；插件注册与产物检查确认无 integration_test 插件。本轮未生成安装器、公开发布或验收真实用户媒体。

## 在线音乐渠道复核（2026-11-02）

- 实际请求：网易云公开搜索和 Audius 搜索/元数据解析通过；Internet Archive 在线测试超时。米兔搜索接口返回 403、枫叶 API 返回 502。上述三个失败项已从可选渠道移除；缺少近期可播证据的其他 LX 实验分支也从选择列表移除，保留最近 Windows 原生验证过的 Hello World/HYW。保留旧歌曲记录格式，避免旧歌单反序列化失败；旧失效渠道不可发起新搜索。
- 用户明确要求先跳过需要登录的 `Netease_url`。复核发现 `flac.music.hi.cn` 的匿名搜索 `ajax.php?act=search` 和试听解析 `act=getUrl` 可用；站内口令针对下载，本应用不调用下载。已接入酷我试听，播放前重新获取签名并校验返回地址，媒体下载标志关闭。在线测试搜得 20 项并解析到 `other-lv.kuwo.cn`，抽样音频 Range 请求返回 206、`audio/mpeg`。`24bit.net` 浏览器首页可见搜索框，但本机应用同类请求遇到 403；暂未把浏览器网页能力宣称为可播渠道。浏览器自动控制因无法可靠确认当前 URL 而停止，未继续操作。需要稳定的可供应用访问的搜索与播放接口才能接入。
- 首页发现以 `music.163.com/api/personalized/newsong` 的公开响应为元数据来源，点击推荐只发送歌曲名与歌手至当前搜索渠道。缓存及内容过滤沿用原路径。尚需设备/真实媒体播放和长期可用性验证。
- 验证：公开首页接口返回 200 和新歌元数据；最终在线源测试 3 项通过（网易云 30 项、Audius 28 项、flac 20 项搜索/解析），移除前 Archive 测试超时。全量 `flutter test --no-pub` 616 项通过、5 项按配置跳过；`flutter analyze --no-pub` 无问题，源码规模检查通过。Windows x64 普通 Release 构建通过，普通插件注册未含 integration_test；未生成安装包，也未在 Android/TV 设备或真实媒体上验收。

## 恶意渠道与跨站攻击增量加固（2026-11-01）

- 在既有渠道防护上统一五个回环服务的请求与响应策略，补齐 Referer/Fetch Metadata、能力 URL 查询别名和拒绝响应保护；修复伪造后缀/越界 Content-Range 可跳过媒体前缀检查的问题。范围与保证边界见 [渠道安全说明](SOURCE-SECURITY-2026-10-29.md#增量加固2026-11-01)。
- 全量 `flutter test --no-pub`：613 项通过、5 项按配置跳过，日志 `build/security-hardening-tests.log`；首轮定向 11 项通过，日志 `build/security-hardening-targeted.log`。规模检查首次报告测试入口函数 105 行，拆分夹具初始化后通过（`build/security-hardening-size-final.log`）；首次失败证据 `build/security-hardening-size.log` 保留。
- `flutter analyze --no-pub` 无问题（`build/security-hardening-analyze.log`）。拆分测试夹具后，网关 5 项复验通过（`build/security-hardening-final-targeted.log`）。
- Windows 原生 3 项业务用例通过（不计 tearDownAll）：安全选项回读、未登记输入拒绝、WAV/HLS 实际播放与引用权限复位，以及 MP4/HLS 的 FFprobe、FFmpeg 声画采样。命令 `./tool/run_windows_native.ps1 -TestFiles @('integration_test/hardening_native_test.dart', 'integration_test/source_security_sampler_test.dart')`；汇总日志 `build/security-hardening-native.log`，原始证据 `.dart_tool/native-043eb4a9/`。驱动仍有既有 integration_test 检测提示，测试成功结果和退出码 0 均已核对。
- Windows 普通 Release 构建通过（退出码 0，`build/security-hardening-windows.log`），产物 `build/windows/x64/runner/Release/zero_player.exe`，需保留同目录 DLL/data；普通插件注册未包含 integration_test。未生成新安装包。下一步为 Android/TV 真机、真实公网媒体和长期播放验收。
- 保留既有 `tmp/` 未跟踪内容；本轮不更新版本、不提交、推送或公开发布，现有安装包尚不含本轮更改。

## v0.0.9 发行与本地测试（2026-11-01）

- 版本更新至 `0.0.9+9`；用户要求提交、打包并推送新版本。正式范围沿用 Windows x64；原 Android 正式密钥文件缺失，不能覆盖正式安装，独立包名的 Android 测试签名包仅作本地测试。原用户音源压缩包保留在本机，不纳入源码或发行附件。
- 同一业务源码此前的全量回归为 611 项通过、5 项按配置跳过（`build/music-enhance-all-tests.log`）；版本更新后版本一致性回归通过（`build/release-0.0.9-version-test.log`），12 项发布工具测试和源码/函数规模检查通过。此前 Windows 原生离线业务回归见下一节，最终静态分析无问题。
- Windows x64 普通 Release 构建通过，版本信息为 `0.0.9+9`（`build/release-0.0.9-windows.log`）。Android ARM64 本地独立测试 Release 构建通过（`build/release-0.0.9-android-test.log`），包名 `dev.zeroplayer.zero_player.devtest`、大小 64.98 MiB；版本、ABI、CRC、随包资源及 v2 测试签名通过，证据 `build/release-0.0.9-apk-verify.log` 和 `build/release-0.0.9-apk-signature.log`。Windows/Android 普通插件注册均无 integration_test。
- 本机测试包 `artifacts/device-test/0.0.9-20261101-083645/` 的 5 个附件 SHA-256、APK/ZIP CRC、APK 与构建产物一致、便携包 93 个 Windows 构建文件一致。此前 `app-release.apk` 保留为 `app-release-before-v0.0.9-20261101.apk`；未安装测试包、修改默认应用或验收 Android/TV 真机及长期播放。
- 正式发行附件、限制和操作说明见 [v0.0.9 版本说明](RELEASE-0.0.9.md)；发行构建及打包入口见 [构建说明](BUILD.md)。

## 音乐聚合搜索与分类优化（2026-11-01）

- 保留接手时全部未提交修改。增加可持久选择的“多源聚合”：6 个非实验渠道、最多 3 路并发，每源 12 秒截止并取消底层请求；按完成顺序增量显示，单源失败隔离，旧搜索取消后不更新结果。同源不同歌曲按渠道/标识去重，聚合分页沿用各源页码。
- 搜索立即合并已完成下载并标明本地播放，在线失败仍可收听；跨源仅使用标题/歌手一致、已知时长相差不超过 2 秒且唯一的本地记录，保留不同版本及歧义。完成记录有内存身份/录音索引，状态更新同步失效；下载进度持久化后直接更新内存，消除每次进度更新重新读取所有下载元数据的开销。空间配额、安全续传、摘要校验、下载权限和监管/网络边界保留。
- 发现页增加榜单/语种/风格/场景分组与 8 份离线可浏览的编辑精选歌单（只保存选曲搜索元数据）；榜单沿用真实源与一小时缓存，重复加载合并，过期缓存先显示再更新。没有接入新的动态歌单 API 或声称个性化推荐。
- 全量 `flutter test --no-pub`：611 通过、5 项按既有公网配置跳过，日志 `build/music-enhance-all-tests.log`。新增 6 项回归，覆盖并发上限/增量结果、超时、取消、下载跨重启索引/删除/跨源匹配、静态歌单离线浏览和网络失败时本地结果；原有三种尺寸/1.6 倍文字发现页回归增加分类切换断言。源码与函数规模检查通过。
- 首轮失败证据保留：`build/music-enhance-music-tests.log`（新增分类令测试按钮位置移出屏幕，改为先滚动到可点击位置）、`build/music-enhance-music-tests-final.log`（整理索引时语法错误，已修复）、`build/music-enhance-music-pass.log`（新组件测试未指定列表滚动目标，已修复）。这些失败不作为通过证据。
- Windows 原生离线业务 1 项通过（不计 tearDownAll）：两首真实下载、完整音轨校验、关闭源站后的离线解码、续播/历史与队列自动连播，日志 `.dart_tool/native-de4890c1/music_offline_native_test.log`、`build/music-enhance-native.log`。驱动仍有既有 integration_test 检测提示，业务成功标记和进程退出码均核对成功。
- 最终 `flutter analyze --no-pub` 无问题（`build/music-enhance-analyze-final.log`），源码/函数规模及差异空白检查通过。普通 Windows x64 Release 构建通过（`build/music-enhance-windows.log`，退出码 0）；`build/windows/x64/runner/Release/zero_player.exe` 需保留同目录 DLL/data，普通插件注册无 integration_test。
- 下一步：真实公网多源性能/成功率与 Android/TV 实机、后台和长时间播放验收；如需交付安装包，应重新按 BUILD.md 打包，现有安装包尚不包含本轮增强。本轮未更新安装包、提交、推送或公开发布。

## 在线音乐核查与修复（2026-11-01）

- 核查搜索、播放/队列、收藏历史、离线任务、推荐和渠道边界，保留接手时所有未提交改动。修复原生错误及播放操作异常后仍显示播放中、故障引擎迟到完成事件误切下一首的问题；失败立即隔离旧事件并释放引擎，保留已知进度，播放按钮可重新解析并续播。打开阶段异常也统一进入停止状态。
- 窄屏播放器将完整歌曲信息、控制按钮和进度工具分行，防止标题和进度条被按钮挤压；补充缓冲中/已播完状态。首次搜索页显示输入引导，不显示空查询页码和无意义翻页；历史、下载内容全部被过滤后显示明确空态。界面验证包含 320/390/844/1280 宽度与 1.6 倍文字，新增窄屏标题实际可用宽度断言；桌面推荐页截图 `build/music-discovery-home.png` 已检查。
- 全量回归 605 项通过、5 项按配置跳过（`build/music-audit-all-tests.log`）；后续窄屏整理后音乐模块 50 项复验通过、3 项公网配置跳过（`build/music-audit-music-final2.log`）。新增回归覆盖故障事件隔离、播放状态复位、异常 seek 后进度保留及重新创建引擎续播。最终静态分析无问题（`build/music-audit-analyze-final.log`），源码/函数规模检查通过。
- Windows 原生 6 项业务用例取得成功：MY FREE MP3 中英文搜索/解码/跳转/暂停、真实下载与离线双曲连播/历史/队列（`.dart_tool/native-2fb11269/`），真实推荐/米兔搜索解码（`.dart_tool/native-bc0d2185/music_discovery_native_test.log`），Hello World/HYW/musicBox 解码（`.dart_tool/native-14aa174f/`）。不计 tearDownAll。HYW 首轮未能播放（`.dart_tool/native-bc0d2185/lx_sources_native_test.log`），独立检查返回有效媒体地址，完整原生重试 3 项通过；保留首次失败，不承诺实验音源持续可用。驱动仍有既有 integration_test 检测提示，业务结果与进程退出码分别核对。
- Windows 普通 Release 构建通过（`build/music-audit-windows.log`），Android ARM64 测试签名 Release 构建通过（`build/music-audit-android.log`），版本沿用 0.0.8+8。APK 64.97 MiB，独立包名 `dev.zeroplayer.zero_player.devtest`、70 MiB 预算及 v2 签名检查通过（`build/music-audit-packaging.log`、`build/music-audit-signature.log`）；普通平台注册无 integration_test。Inno 安装器编译成功。
- 交付 `artifacts/device-test/0.0.8-20261101-080757/`：Windows 安装器 67.58 MiB、便携 ZIP 88.51 MiB、Android ARM64 APK，另附依赖声明/来源、TEST-INFO 和 SHA256SUMS。393 个构建输入指纹保持一致，5 个交付附件摘要及 APK/ZIP CRC 通过，便携包 93 个构建文件逐字节一致，双端随包音乐目录和频道预检表与源码一致；未包含本机数据库或签名私钥。报告 `build/music-audit-package-verification.json`。未安装到用户环境，保留全部旧包。
- Android/TV 实机、系统后台及长时间播放仍待验收；本轮不改变脚本执行、监管、内容过滤、网络授权或正式签名边界，不提交、推送或公开发布。

## 音乐队列与下载稳定性（2026-11-01，当前源码）

- 继续保持原生逐源适配、不执行远程脚本的约定。本轮梳理播放队列、渠道记忆、进度拖动、过滤变更和离线任务；未改变既有音源协议、网络授权、监管边界或发行版本。本地 v6 等尚未完成的源仍按下节边界处理，不将其标为已兼容。
- 歌曲菜单新增“下一首播放”和“加入播放队列”，覆盖搜索、历史、歌单及已下载歌曲；队列按渠道/歌曲 ID 去重，最多 500 首。播放器与迷你播放器提供队列弹窗，支持切歌、上移/下移、移出和清空其他歌曲。编辑其他条目保留当前引擎/进度；移出当前歌曲后播放后继，最后一首移出后停止。队列仍为本次运行会话，持久收藏使用歌单。
- 过滤规则更新时移除队列中受限的后续歌曲，避免自动连播停在被屏蔽项；当前歌曲受限仍停止。列表循环的上一首支持从队首回队尾。重试解析保留最后播放位置。进度拖动只更新预览，松手后执行一次 seek，避免持续重启媒体请求。
- 本机渠道偏好存入 `app_meta.music_provider`，异步恢复不能覆盖用户新选择；关闭等待偏好写入，损坏或已移除的渠道回退默认。该偏好属于本机，不进入歌单/历史备份。搜索保留受控客户端提供的超时/HTTP 等失败信息，并区分过滤规则拒绝。
- 下载暂停改为等待指定活动任务，排队暂停/删除无需等待其他歌曲。取消与替换按具体 token 识别，旧任务不能删除新任务的取消句柄，也不会在移除后重新创建记录。续传预算补回当前部分文件或 HLS 保留资源的已有占用，其他任务和文件继续计入总额，修复接近 1 GiB 上限时重复扣除续传空间的问题。LX 和米兔的下载限制集中到领域属性，即使导入记录声明可下载也不能绕过。
- 全量单元/界面回归 602 项通过、5 项配置跳过（`build/music-v4-all-tests.log`）；音乐模块新增 15 项回归，覆盖队列去重/容量/编辑/过滤后连播/重试进度、渠道恢复竞态和错误说明、两类下载取消/替换、容量附近续传及三种尺寸/1.6 倍文字下的队列与进度拖动。静态分析无问题（`build/music-v4-analyze-clean.log`），源码/函数规模检查通过（`build/music-v4-size-final.log`）。早期 lint 与异常模式匹配顺序问题已修正，失败日志保留。
- Windows 原生业务 6 项通过（不计 tearDownAll），证据 `.dart_tool/native-1bbb4876/`、`build/music-v4-native.log`。增强离线用例已验证源站关闭后的两首真实解码/自动连播、队列弹窗整理与两条历史记录；推荐封面/米兔搜索解码、Hello World/HYW/musicBox 解码、MY FREE MP3 中英文搜索与播放控制保持通过。驱动仍有既有 integration_test 检测提示和 Windows AXTree 日志，业务结果与退出码成功。
- 普通 Windows x64 Release 构建通过（`build/music-v4-windows.log`），程序 `build/windows/x64/runner/Release/zero_player.exe` 需保留同目录 DLL/data，普通注册不含 integration_test。Android ARM64 Debug 构建恢复后通过（`build/music-v4-android-recovered.log`，退出码 0），APK CRC 完整且仅含 arm64-v8a；旧 APK 已保留为 `app-debug-before-music-v4-20261101-030508.apk`。两个运行包的音乐清单/频道预检表均与源码一致，AOT/APK 摘要确认已更新，结果 `build/music-v4-artifact-verification.json`。
- 首次 Android 任务在依赖解析阶段中断；重试与 Gradle dry-run 均复现 FlutterTaskHelper.readDependencies 的 IndexOutOfBounds。确认 4 份生成依赖清单完全为零填充后，逐文件核验绝对路径及内容，改名保留原件，再重新构建成功；没有清空构建目录或修改 SDK。恢复记录 `build/music-v4-depfile-recovery.json`，失败证据 `build/music-v4-android-retry.log`、`build/music-v4-android-stacktrace.log`；重新生成的 `flutter_build.d` 已校验正常。
- 下一步仍为 Android/TV 实机、系统后台、长时/长列表体验及更多原生音源适配；本轮未验收这些项目，也未提交、推送、发布或生成新安装包，既有测试安装包未更新。

## 音乐推荐首页与逐源原生适配（2026-11-01，阶段记录）

- 用户明确选择保持“不执行远程脚本”的规则，继续逐源原生适配。未加入 JavaScript、Python 或 JAR 执行器，未降低 TLS、私网、成人过滤或监管限制。所有脚本只在忽略的检查目录中作为文本分析；随包清单只包含来源、版本、固定 SHA-256 和适配状态。
- 首次进入音乐显示“发现音乐”，使用真实网易云热歌/新歌/原创/飙升榜单和 WFU 音乐主题；复用视频 PosterCard/PosterImage 与受控图片缓存，按专辑方形排列，点击封面以歌名和歌手通过所选渠道搜索。参考 Navidrome 的封面库组织方式，用 Flutter 原生实现，无需部署 Navidrome 服务。推荐按榜单缓存一小时，失败显示已有缓存，损坏缓存重新获取；文字继续经过内容过滤。
- 新增米兔（QQMP3）歌曲搜索和酷我解析、枫叶 musicBox 网易云搜索/Meting 播放。米兔需固定站点请求头，云盘分享不自动导入且不提供下载。WFU 仅提供推荐主题，不提取 YouTube 嵌入流；UZZ 当前 403，未发现可验证协议，不列入播放选择。原生网站协议回归覆盖分页、图片、正常请求头与不安全地址拒绝。
- pdone 仓库 16 项加本地 v6 修复包逐项登记：原生分支扩展为 Huibq、幻音、QDY、星海、杰翔独家公共 v4、Hello World、HYW 公益版、野花、野草和聚合直链，共 10 项有限分支。大多数仅支持网易云 128k；野草按源方声明使用酷我 ID/128k，米兔供搜索元数据。聚合仅接受固定 POST 直链响应，拒绝远端 303 动态请求指令。POST 复用受控客户端，限制请求体 64 KiB，禁止重定向和自动重试；回归验证私网拒绝和请求体不向重定向目标转发。
- 未实现全部脚本平台/音质/回退行为，不能称为完整 LX 兼容。长青的固定协议已还原但媒体入口 404；野花/野草静态字符串表和 tag 格式已还原，实测媒体入口也 404。Huibq 曾 503、QDY/星海 403、幻音 TLS 失败、聚合初始化 429；这些状态不等于正常播放。IKUN 无公开密钥，fish/lx/sixyin/yuningxi 的混淆协议及本地 v6 的虚拟机协议仍待原生还原，不提供未适配项的播放选择。检查证据 `build/music-v3-inspection/`，摘要清单 `assets/catalogs/music/lx-native-catalog.json`。
- 用户本地 `tmp/lx-music-source-v6 (修复).zip` 已读到并静态检查；其中 64,094 字节脚本的 SHA-256 为 `ef5289ddc2e8fd98ec7ac9e096878d9e6fed5e4ae1669d21e4484eac247aeda7`。只记录检查结果，没有执行或打包该脚本；杰翔的公共 v4 分支不冒充 v6 修复包。
- LX Open API 实现手动启用的只读子集，默认关闭，仅监听随机 IPv4 回环端口；提供 `/status` 字段过滤、空歌词端点和逐字段 SSE，最多 4 个订阅。拒绝浏览器 Origin/Sec-Fetch 请求，不提供播放控制或任意 URL 代理，退出关闭。它是本机状态接口而非在线歌曲源，未宣称全部官方 Open API 兼容。
- 本轮全量单元/界面回归 587 项通过、5 项按配置跳过（`build/music-v3-all-tests.log`）；随后修正发现页切换渠道时的旧搜索上下文，音乐模块 32 项复验通过、3 项公网跳过（`build/music-v3-music-final.log`）。新增 UI 回归覆盖 390/844/1280 三种尺寸与 1.6 倍文字、封面点击搜索；最后补查渠道弹窗异步目录加载与列表滚动，三种尺寸均通过（`build/music-v3-dialog-final3.log`）。早期夹具跨 fake-async 资源清理、资产 IO 未让出真实事件循环导致的失败已修正，失败日志保留。最终源码/函数规模检查通过（`build/music-v3-size-verified.log`），静态分析无问题（`build/music-v3-analyze-verified.log`）。
- Windows 最终原生业务 6 项通过（不计 tearDownAll）：80 首真实推荐、封面到所选渠道搜索及米兔 30 项结果解码；Hello World、HYW 公益与 musicBox 分别完成公开样本解码；原有真实下载/离线解码/历史续播及 MY FREE MP3 中英文搜索/跳转/暂停保持通过。证据 `.dart_tool/native-f56907f8/`、`build/music-v3-native-final.log`，截图 `build/music-v3-home.png` 已检查。驱动仍有既有 integration_test 检测提示与 Windows AXTree 日志；不将短时解码称为完整曲目或长时稳定性验收。
- 普通 Windows x64 Release 构建通过（`build/music-v3-windows.log`），程序 `build/windows/x64/runner/Release/zero_player.exe` 需保留同目录 DLL/data；普通注册不含 integration_test。Android ARM64 Debug 构建通过（`build/music-v3-android.log`），APK CRC 完整且只含 arm64-v8a；旧 APK 已另存备份。两个运行包内的音乐适配清单和频道预检表均与源码逐字节一致，音乐目录没有可执行脚本；摘要与检查结果见 `build/music-v3-artifact-verification.json`。Android/TV 实机与长期播放仍未验收；未提交、推送、公开发布或生成本轮新安装包。

## 音乐功能本地测试包（2026-11-01，先前测试包）

- 按用户要求打包当前音乐功能源码，沿用版本 `0.0.8+8`；没有提交、推送或公开发布。产物目录 `artifacts/device-test/0.0.8-20261101-013022/`，包含 `zero-player-0.0.8-windows-x64-setup.exe`、`zero-player-0.0.8-windows-x64-portable.zip`、`zero-player-0.0.8-android-arm64.apk`、第三方声明/原生来源 ZIP、`TEST-INFO.txt` 和 `SHA256SUMS.txt`。旧测试包及已发行附件均保留。
- Windows x64 普通 Release 重新构建成功（`build/music-test-package-windows.log`）；Inno Setup 安装器编译成功（`build/music-test-package-packaging.log`）。Windows 沿用原应用身份，便携包必须完整解压。Android 使用独立包名 `dev.zeroplayer.zero_player.devtest`、应用名“Zero Player 测试”及既有本机测试签名，构建类型为 Release，可与正式版并存；未改变正式签名策略。构建日志 `build/music-test-package-android.log`。
- APK 64.93 MiB，版本、包名、arm64-v8a 原生完整性、70 MiB 预算和可选模型排除检查通过（`build/music-test-package-apk.log`）；APK v2 签名验证通过（`build/music-test-package-signature.log`）。普通 Windows/Android 注册均不含 integration_test，未手改生成文件。
- 沿用同一源码已通过的 576 项单元/组件回归、5 项配置跳过及 2 项 Windows 原生业务验证；本轮重新构建和打包期间 651 个输入文件指纹保持一致（`build/music-test-package-source.json`）。5 个交付附件全部复核 SHA-256，APK/ZIP CRC 完整；便携包 EXE 和 AOT 与本轮 Windows Release 一致，APK 与本轮构建一致，运行包未包含本机数据库或签名私钥。汇总 `build/music-test-package-verification.json`。
- 本轮只构建和核验测试交付物，未安装到实际用户环境、修改默认应用或验收 Android/TV 实机、安装后关联/卸载与长时播放。Huibq 503、Internet Archive 超时等音源边界已写入包内测试说明。

## 音乐库与多音源扩展（2026-11-01，当前源码）

- 音乐页分为搜索、我的歌单、播放历史和离线音乐。歌单支持新建、重命名、删除、加歌、移出和排序；同歌曲按渠道与远端 ID 去重。最多 100 个歌单、每单 500 首，顺序/列表循环/单曲循环/随机模式保存到本机。历史保留 200 首，播放时节流保存，暂停/停止/退出补记，支持点选续播和清空。歌单、历史和模式使用现有 app_meta，不改数据库版本；纳入普通备份并校验数量、字段及地址，下载任务/文件不随备份迁移。
- 音源保留默认 MY FREE MP3，新增网易云公开音频、Audius 和 Internet Archive；新增 LX/Huibq 原生 HTTP 解析及 pdone/lx-music-source 的 16 项版本检查目录。未执行、求值或自动加载远程脚本；其余目录项尚未适配播放，不能当作可播源。网易云公开音频不保证付费、地区限制或下架资源可播；Audius 排除受访问条件限制的歌曲，下载前重新检查公开下载标志。Huibq 不提供下载。
- 音乐下载按单任务串行执行，复用强 ETag 安全续传、HLS 清单/分片下载及离线能力 URL；直接音频通过仅 file 协议的完整音轨解码校验，离线重播复核摘要。每首 128 MiB、合计 1 GiB、最多 500 项，计入保留的部分文件和 HLS 固定分片；暂停、失败和退出保留可恢复数据，重启持久恢复为暂停，需手动继续。损坏/缺失标记失败，播放中的文件拒绝删除。媒体仍经过原生输入检查，只有离线服务已注册资源可绕过再次代理；没有开放任意本机/私网地址。
- 通过音源元数据公网请求确认网易云 30 项、Audius 28 项搜索结果及原生地址解析；不将元数据返回地址等同于实际解码成功。Internet Archive 本机请求超时，Huibq 探测返回 HTTP 503；进一步静态检查的 QDY/GD 接口返回 403、幻音备用接口 TLS 中断，本轮未把它们伪装成可用渠道。证据 `build/music-v2-online.log`；普通回归默认跳过三项公网用例，显式入口见 BUILD.md。
- 最终全量回归 576 项通过、5 项按配置跳过（既有 2 项及新增 3 项公网音源测试），日志 `build/music-v2-all-final.log`。静态分析无问题（`build/music-v2-final-analyze.log`），源码规模检查通过（`build/music-v2-size-final.log`）。新增回归覆盖跨重启歌单/历史/模式、备份、四种完成行为、下载重启/中断状态、容量、摘要损坏及活动文件保护。早期全量回归发现音乐下载依赖提前创建影响隐藏窗口清理，已改为首次使用音乐时初始化，既有隐藏窗口回归与音乐针对性 25 项复验通过（`build/music-v2-close-regression.log`）。
- 最终 Windows 原生 2 项业务用例通过（不计 tearDownAll）：合成音频真实下载和完整性验证、关闭源站后的本机能力 URL 解码、跳到 3 秒及历史持久化；既有 MY FREE MP3 中英文搜索与真实音频解码/跳转/暂停回归。最终证据 `.dart_tool/native-a6e6d759/music_offline_native_test.log`、`.dart_tool/native-a6e6d759/music_native_test.log`、`build/music-v2-native-final.log`。驱动仍有既有插件检测提示，但业务结果及退出码成功。初次证据 `.dart_tool/native-3d6664bf/` 保留。
- Windows x64 普通 Release 构建通过（`build/music-v2-windows.log`），产物 `build/windows/x64/runner/Release/zero_player.exe` 需保留同目录 DLL/data，普通注册不含 integration_test。Android ARM64 Debug 构建通过（`build/music-v2-android.log`），APK CRC 完整且仅含 arm64-v8a；这是 Debug 编译验收，不是正式 Release 或设备验收。产物摘要见 `build/music-v2-artifact-verification.json`；原 APK 保留为 `app-debug-before-music-v2-20261101-004244.apk`，没有更新已发行附件。
- 下一步为 Android/TV 实机、系统后台任务、音乐托盘关闭/恢复和长时播放验收；源站长期可用性不在本轮结论内。本轮未提交、推送、安装到真实用户环境或发布新安装器，之前的发行附件保持原样。

## 在线音乐（2026-10-31，阶段记录）

- 菜单新增“在线音乐”，默认使用 `https://myfreemp3.ink` 及该站公开浏览器搜索协议。独立 music 模块承担临时签名、HTML 歌曲解析、分页、取消/覆盖旧搜索、列表播放、过期地址刷新和界面。推荐搜索为应用固定快捷词，首次进入搜索“周杰伦”；不将其描述为源站排行榜。
- 当前页搜索结果组成连续播放列表，支持上一首/下一首、进度跳转、音量、暂停和停止。离开页面保留当前会话搜索与队列，并显示迷你播放器；Windows 托盘通过统一音频会话控制最近使用的音乐或广播。音乐、广播互相暂停，打开视频暂停两者。未新增数据库表、音乐下载/收藏/歌词或自定义音乐渠道。
- 搜索、列表和播放前均检查渠道/标题/歌手的成人与监管关键词过滤；规则更新后停止受限歌曲。歌曲与 HLS 引用继续经过现有媒体网关、网络目标检查和原生输入限制，不运行远程脚本。文字过滤不代表对实际歌曲音频完成审查。
- Windows 真实公网原生用例通过 1 项业务用例（不计 tearDownAll）：中英文搜索各 40 首，真实 286 秒音频经受控网关解码、跳到 10 秒、暂停与停止。证据 `.dart_tool/native-2b887302/music_native_test.log`、`build/music-native-verified.log`。早期原生失败定位为 mpv 默认 5 秒网络等待短于源站约 5 秒首次响应；仅音乐显式设置并核验 30 秒等待，其他播放器默认值保持。失败证据保留在 `.dart_tool/native-708bfe55/`、`.dart_tool/native-be680b2f/`、`.dart_tool/native-31c51776/`。
- 全量单元/组件回归 567 项通过、2 项按原配置跳过（`build/music-all-tests.log`）；新增 12 项覆盖签名更新、中文分页、协议/私网拒绝、搜索取消、超时后禁止迟到播放、监管变更、队列/进度/互斥和 390/844/1280 布局及 1.6 倍文字。静态分析无问题（`build/music-final-analyze.log`），源码规模检查通过（`build/music-source-size.log`）。早期测试中的 URI 编码预期、响应字符集与 fake-async 夹具已修正，失败日志保留，不作为业务成功证据。
- Windows x64 普通 Release 构建通过（`build/music-windows-release.log`），产物为 `build/windows/x64/runner/Release/zero_player.exe`，需保留同目录 DLL/data；普通 Windows 注册文件不含 integration_test。Android ARM64 Debug 构建通过（`build/music-android-debug.log`），APK CRC 完整且仅含 arm64-v8a。Android Debug 正常包含开发依赖注册，不将其作为正式 Release 包验收；未手改生成文件。两平台产物 SHA-256 与检查结果见 `build/music-artifact-verification.json`，旧 APK 保留为 `app-debug-before-music-20261031-233237.apk`。
- 下一步：Android/TV 实机、系统后台播放、Windows 音乐托盘关闭/恢复、长时间收听验收；源站长期可用性不在本轮结论内。本轮未生成新安装器、提交、推送、安装到真实用户环境或公开发布，v0.0.8 已发行包保持原样。

## v0.0.8 正式发行范围（2026-10-31）

- 用户已授权提交、推送和发布；当前已验证业务源码指纹与上一轮复查/打包一致，本轮仅更新发行文档。使用版本 `0.0.8+8`、标签 `v0.0.8`，正式发行仅含 Windows x64 安装器/便携包及源码、依赖声明、原生来源和 SHA-256 清单。
- 原 Android 正式签名文件仍不可用，本版不上传独立包名/测试签名 APK 为正式附件，保留 v0.0.7 Android 下载。本轮未更改签名、监管、用户数据或系统默认应用。
- 已验证基线：555 项回归通过、2 项跳过；Windows 原生业务 4 项通过；静态分析、源码规模和 Python 工具回归 12 项通过，见上轮 repackage 日志。发行附件基于同一普通 Windows Release，源码 ZIP 从审阅后的 Git index 固定快照生成，并核对到发行提交；不包含本地密钥或数据。安装后关联/卸载、Android/TV 实机和真实媒体长时播放仍未验收。
- 发布入口：https://github.com/yixunfei/zero-player/releases/tag/v0.0.8 。本地发行附件位于 `artifacts/release/0.0.8/`，校验和以该目录 `SHA256SUMS.txt` 为准；历史测试包保留。

## 复查通过与重新打包（2026-10-31 17:21，Asia/Shanghai）

- 基于当前工作区复查原 8 项问题及后续三项 P2 闭环；未发现本轮打包阻断项，未修改业务源码。555 项全量单元/组件回归通过、2 项按原配置跳过（`build/repackage-recheck-tests.log`）；静态分析无问题（`build/repackage-analyze.log`）；源码规模检查及 12 项 Python 工具回归通过（`build/repackage-python.log`）。
- Windows 原生 4 项业务用例通过（不计 tearDownAll）：隐藏/最小化窗口跨进程文件转发、实际本地解码/跳转/续播/导出后重播、HLS 下载保存和小窗/全屏恢复；日志 `.dart_tool/native-04def3ad/`、`build/repackage-native.log`。驱动仍有既有插件检测提示，业务结果及退出码成功。所有用例使用隔离数据，未启动真实用户数据中的播放任务。
- Windows 普通 Release 构建通过（`build/repackage-windows.log`）。Android ARM64 测试签名 Release 构建通过（`build/repackage-android-verified.log`），独立包名 `dev.zeroplayer.zero_player.devtest`，版本 `0.0.8+8`，可与正式版并存。APK 包名、版本、原生 ABI、70 MiB 预算及 v2 签名验证通过（`build/repackage-apk-validation.log`、`build/repackage-apk-signature.log`）。
- 首次 Android `--no-pub` Release 失败：原生测试残留的 integration_test 注册项进入普通 Java 编译，失败证据 `build/repackage-android.log` 与 `build/repackage-android-registrant-before.java` 保留；通过不带 `--no-pub` 的普通构建入口重新生成注册后成功。未手改生成代码、替换 DLL 或清空缓存；构建说明已补充该复现条件。
- 使用现有 `package_release.ps1 -DeviceTest -AndroidArm64Only` 流程重新打包，依赖声明和原生源码材料均重新收集/校验。最新交付目录：`artifacts/device-test/0.0.8-20261031-172151/`，含 Windows 安装器/便携包、Android ARM64 APK、第三方声明/原生来源 ZIP 和 `SHA256SUMS.txt`。旧安装器均保留，勿与本次新包混用。
- 交付文件摘要全部重新核对通过；便携包及 APK ZIP CRC 完整，便携包 EXE 与本轮 Release 一致。Windows/Android 普通注册文件均不含 integration_test；583 个复查源码文件的指纹在验证和打包期间未变化。证据 `build/repackage-reviewed-source.json`、`build/repackage-artifact-verification.json`、`build/repackage-packaging.log`。
- 安装器 SHA-256：`695ea946d69600064eddb236164e834c64b714ca289a950658e320d585a0d655`；便携包：`9942b2089091974c17bd00e3aca1f86bee26d42a0459698cc5ed4136fb41fea7`；APK：`b3d939ed9cfc63ab94de5b455104072fedcea83f43566c1faa41c5cbf4b20412`。
- 本轮“通过”范围为代码复查、本机回归、Windows 原生业务和构建/包校验。Android/TV SAF 实机、真实用户媒体长时播放、安装/卸载后的系统关联仍未验收；未安装、更改系统默认应用、提交、推送或公开发布，全部已有未提交改动保留。

## 三项 P2 闭环（2026-10-31）

- 隐藏窗口转发先直接 await 原生显示/恢复，再等待帧导航；请求序号抑制过期路由，退出/销毁后不再导航。隔离临时目录及内存数据库的真实 Windows 测试覆盖隐藏首页（无视频帧）、暂停后最小化、连续与重复文件的实际恢复及解码：`.dart_tool/native-9f0bdd5f/forwarded_video_native_test.log` / `build/p2-native-final.log`。最初两次夹具未关闭默认全屏，最小化前置条件失败，日志保留，不算业务通过。
- 历史入口返回后“选择视频文件”打开独立记录；失效历史增加明确“重新定位原记录（保留进度）”。Android 文档身份优先于 previousId，另一文档不会继承旧记录，同文档跨副本仍按稳定身份续播。正式页面测试验证成功历史入口选新文件及失效路径显式重新定位；组件和领域回归保留。
- 下载先在数据库持久化随机发布文件名、目录及导出内容 SHA-256，再发布。Windows/Android SAF 重启核验该身份的实际内容，一致才补记完成；不根据普通同名文件认领，不覆盖用户目标。SAF 提供者必须保留请求名称；授权撤销、内容不一致或残留不完整目标保守失败，界面可重新选择目录，完整缓存保留。旧版本没有意图的已发布文件不自动认领，重试以新随机名称另存，旧文件保留。取消和失败沿用完整缓存及不覆盖发布保护；删除任务同时删除发布意图。
- 全量回归 553 通过、2 项按原配置跳过（`build/p2-all-tests-verified.log`）；后补页面交互测试及整理后的正式新增回归共 6 项通过（`build/p2-final-targeted.log`），现有保存/本地测试 9 项通过（`build/p2-targeted.log`）。静态分析无问题（`build/p2-analyze-final.log`）。早期新增断言的路径分隔符差异和组件夹具异步等待不足已修正，失败日志保留。
- 普通 Windows Release 构建通过（`build/p2-windows.log`），生成插件注册无 integration_test；EXE SHA-256 `da4658fd809efac17c576252f77a2310a83356a0dda84f5fbe4eb21ea50edbe0`，需保留同目录 DLL/data。Android ARM64 Debug 编译通过（`build/p2-android.log`），APK CRC 完整且仅 arm64-v8a；SHA-256 `811ba4d11a3ce2610d88518537a7f9fa4d10f27d6eb8c81feac99e351887c15e`，旧 APK 保留于 `app-debug-before-p2-20261031.apk`。
- 本轮未重打安装器；下文旧安装器均不包含此次三项修复。Android/TV SAF 实机（含权限撤销、空间不足及进程终止）、安装后 Shell 关联/卸载、真实用户媒体仍未验证。SAF 中断残留或内容不一致时需重新授权/更换目录，不自动删除外部文件。所有测试使用显式隔离数据；保留全部未提交改动，未提交、推送、公开发布或修改系统默认应用。
- 下一步：Android/TV 实机验证上述 SAF 边界；如需安装器，必须基于本轮最终普通 Release 重新编译及记录摘要，不能混用旧包。

## 再次复核（2026-10-31，仍有三项遗漏）

- 按当前工作区（含后续补修）复核原 8 项问题，未修改业务源码、未启动实际用户数据目录中的程序。目录独占、待保存状态和遗留内部临时文件清理、失效记录重选入口、离线标记能力限制、横屏滚动、小窗/清理失败退出、首页历史订阅及 Android 流式副本配额/清理均已有对应实现和正向测试。
- 本轮重跑完整回归 549 项通过、2 项按既有配置跳过，日志 `build/final-recheck-all-tests.log`。另在忽略目录 `build/final_recheck_probe_test.dart` 编写 3 项补充探针，均命中预期异常，日志 `build/final-recheck-probes-verified.log`。首次夹具缺少启动全屏 mock 且跨 fake async 关闭超时，失败日志 `build/final-recheck-probes.log` 保留，修正夹具后验证；探针通过只表示复现成功。
- [P2] Windows 文件转发在 hidden 生命周期下不能主动唤醒：ProductApp 先把 revealWindow 放进 addPostFrameCallback，再 scheduleFrame；此时 framesEnabled=false，恢复窗口所需操作本身也被卡住。组件生命周期探针确认转发后 show 调用为 0，直到恢复生命周期；需在等待帧之前先显示/恢复窗口，再调度路由。原生转发测试覆盖正在解码的可见窗口，没有覆盖隐藏/最小化窗口。
- [P2] 从历史 id 页面播放后，再点“选择视频文件”选另一部视频时，LocalVideoPage 始终传 previousId；LocalVideo 优先 previousId 并忽略新文档 identity，导致另一视频沿用旧 ID/进度并重写路径映射。探针用文档 A 的 20 秒进度选择文档 B，确认 B 仍取得 A 的 ID 和 20 秒。应将“重新定位本记录”和“打开新视频”分开，避免静默串记录。
- [P2] 外部视频已发布、download_saved 事务尚未提交时崩溃仍无法幂等恢复：恢复为 pendingSave 后，重新导出总会遇到已有目标且失败。探针保留与缓存内容一致的已发布目标但无 saved 记录，连续两次重试均失败且无法写入完成凭据。需在发布前持久化保存意图/身份并校验一致内容后认领或提供明确恢复操作，不能盲目覆盖用户文件。
- 交付物核验：当前测试安装器 SHA-256 与 `build/remaining-fixes-sha256.txt` 一致（B67C3DAF74BA2EFC7BE056BF137F48C15992A6A25E09103B142B529B6117B7B1），Release EXE 也与记录一致（DB70D88CCEBD7880CE4BFB1AA6DCDBB350605F07C302C5BD7E8C3EE7C255CE04）。本轮未重建、安装或验收 Android/TV 真机与 Windows Shell 关联。

## 独立复查剩余问题修复（2026-10-31）

- 保留前序全部未提交改动，在当前工作区继续实现；未推送或发布。播放器退出将引擎关闭、窗口恢复和路由退出分开执行；清理失败仍返回，记录错误并提供“重试恢复窗口”提示，不再停留在已关闭播放器的等待页。
- Android 视频选择桥接返回原文档 URI 的 SHA-256 身份（不持久化原始 URI），本地播放以文档身份而非 UUID 缓存路径派生记录 ID。同一文档重选后续播，另一文档独立记录；旧记录仍保留从历史入口重新定位。副本复制、取消、容量和原文件保护保持。选择页增加滚动，覆盖横屏和 1.6 倍文字。
- Windows 目录所有权锁下增加受随机令牌保护的回环文件转发入口。第二进程在取得锁失败后，仅转发绝对本地视频路径并退出，不初始化数据库或缓存。现有窗口恢复可见性，替换播放页；重复打开同一路径也会重新处理。入口拒绝无令牌/网页来源/网络 URL，有体积、排队数量和超时限制；关闭服务前停止接收，保留所有权锁直至资源关闭完成。所有播放请求继续经过本地资源与监管检查。
- 全量单元/组件回归 549 通过、2 项按原配置跳过（`build/remaining-fixes-all-tests.log`）；最终针对性 9 项通过（`build/remaining-fixes-final-targeted.log`）。新增正向断言验证双重清理失败仍导航、跨副本续播、横屏放大文字、真实独立进程转发及未授权请求拒绝。12 项 Python 工具回归通过（`build/remaining-fixes-python.log`）。早期新增测试夹具遇到 fake async 清理超时/HTTP stub 和 Socket 流类型错误，失败日志保留，修正夹具后复验。
- Windows 原生 4 项业务用例通过（不计 tearDownAll），日志 `.dart_tool/native-2c17d2a5/`：真实独立进程向正在播放的窗口连续转发中文路径视频并重复打开同一文件，均进入实际解码；HLS 下载保存；本地解码/跳转/续播/导出后重播；小窗及全屏恢复。原生 driver 仍有既有插件检测提示，业务结果与退出码成功。原生测试使用显式临时目录与内存数据库，没有启动已安装程序或触及实际用户数据目录。
- 最终针对性回归 10 项通过（含停止接收后仍持有所有权锁的断言，`build/remaining-fixes-targeted-complete.log`）；静态分析无问题（`build/remaining-fixes-analyze-clean.log`），源码/函数规模检查和差异检查通过。Windows 普通 Release 构建通过（`build/remaining-fixes-windows.log`），普通插件注册无 integration_test；Android ARM64 Debug 构建通过（`build/remaining-fixes-android.log`），APK CRC 完整且仅含 arm64-v8a。旧 APK 已备份为 `app-debug-before-remaining-fixes-*.apk`。
- 新安装器编译通过（`build/remaining-fixes-installer.log`）：`build/remaining-fixes-installer-20261031/zero-player-0.0.8-windows-x64-setup.exe`，包含本轮重建后的 Windows Release；旧安装器保留，不再作为当前测试入口。安装器、APK 和 EXE 的 SHA-256 在 `build/remaining-fixes-sha256.txt`。本轮未安装到实际用户环境、修改默认应用、提交或推送。
- Android/TV 实机文档选择与安装后的关联/卸载仍未验收；新协议的独立进程发送及现有窗口接收/解码已验证，但不将其等同于安装后的 Windows Shell 关联验收。旧版本进程不识别新锁与转发协议，升级前应退出旧版本。

## 全模块审查问题修复（2026-10-31）

- Windows 在打开数据库、恢复下载和清理分片前锁定应用数据目录；同目录的第二个新版本进程提示使用现有窗口，不执行初始化。锁持有到服务全部关闭；关闭失败时保留锁至进程退出。隔离目录中的独立进程测试覆盖冲突、正常释放及异常退出后的接管，并核对第二次 `AppServices.create` 不创建数据库、不删除在途分片（`build/review-owner-initialization.log`）。此方案不转发文件参数，也不能约束不遵守该锁的旧版本进程。
- 下载缓存完成与目标目录保存分别持久化为 `pendingSave`、`saving` 和 `complete`，启动时恢复待保存任务；中断、失败或取消仍保留完整离线缓存。保存使用任务内独立临时目录并清理旧版 `output.mp4` / 中断目录；Windows 使用不替换已有文件的原生发布操作，Android 检查文档目标并只清理本次创建的文档。若崩溃发生在目标发布后、数据库记录前，重试会保守拒绝同名文件，需用户核对或更换目录。
- 本地记录读取放入仓库，失效记录允许重新选择并沿用原记录身份和续播进度。区分在线、直播、下载和本地媒体能力；本地/下载视频禁用特征采集及标记并说明原因。下载选集改为可滚动布局，覆盖手机横屏、长标题/路径和放大文字。Windows 小窗串行恢复原边界、置顶和最大化，并处理应用全屏与恢复失败后的重试。首页订阅观看历史领域变化，进度更新无需重载首页或重置滚动；内容记录和本地映射不再广播为通用 `app_meta` 来源变更。
- Android 本地视频仍流式复制到应用私有缓存，增加复制进度、取消、独立容量核算与低空间保护；清理缓存包含未使用本地副本，保护正在播放的副本，不删除用户原文件。清理或系统回收后，失效记录可重新选择文件。继续使用原监管和过滤规则，不将本地选择视为监管授权。
- 全量 Flutter 回归 544 通过、2 项按原配置跳过（`build/review-fixes-full-tests-verified.log`）；此后小窗失败恢复调整及相关入口的 30 项针对性回归通过（`build/review-fixes-targeted-last.log`），历史刷新在非零滚动位置另行通过（`build/review-history-scroll.log`）。首次全量运行的 2 个旧夹具失败及修正前日志保留于 `build/review-fixes-full-tests.log`。`flutter analyze --no-pub` 无问题（`build/review-fixes-analyze-final.log`；分析配置排除保留的 `build/` 临时探针），Python 发布工具回归 12 项和源码规模检查通过。
- Windows 原生 3 项业务用例通过：HLS 下载保存、本地视频解码/跳转/续播/导出后重播、小窗及全屏恢复；日志 `.dart_tool/native-03910f1a/`。驱动仍有既有插件检测提示，但业务结果和退出码成功。Windows 普通 Release 构建通过（`build/review-fixes-windows-verified.log`），生成插件注册不含 integration_test；产物需保留同目录 DLL/data。
- Android ARM64 Debug 最终编译通过（`build/review-fixes-android-final-verified.log`），APK CRC、版本 `0.0.8+8` 和 ABI 校验通过，SHA-256 `f43fcb42ad8e3f75c8a27afdf3fadb6812e7c66b7f5c8dc3a1743a719a703769`。调试包约 163.30 MiB，校验工具提示 ZIP 填充较大，仅供本地调试；复制进度/取消、低空间与 SAF 行为尚未在 Android/TV 实机验收。未推送、发布或修改默认应用。
- 探针更正：本轮最初用环境变量尝试隔离旧版双进程，但 Windows 路径插件使用系统已知文件夹，该探针实际触及 `AppData/Roaming/Zero Player contributors/Zero Player` 的数据库和缓存初始化。事后只读查询时下载任务数为 0；数据库修改时间已被触及，不能确认此前是否存在被启动清理的 `.part`，也不能声称完全隔离。后续所有锁测试使用显式临时目录，原生业务测试使用各自临时目录和内存数据库。

## 修复后独立复查（2026-10-31，仍有未闭环项）

- 确认修复会话已结束，审查当前未提交源码；本轮未修改业务源码，也未启动实际用户数据目录中的程序。重跑锁、小窗、首页历史、本地/下载交互和下载保存相关 16 项测试全部通过（`build/recheck-review-targeted.log`）。另在忽略目录写入两个补充探针（`build/recheck_remaining_probe_test.dart`），均命中预期异常（`build/recheck-remaining-probes.log`）；不把异常复现当成功验收。
- 待修复：PlayerPage._leave 先置 leaving/closed，再 await restorePlayerWindow。若窗口恢复抛错，路由退出不会执行，页面显示等待且后续返回被 leaving 拦截；平台层重试测试没有覆盖播放页这一失败闭环（代码确认，未做原生故障注入）。
- 待修复：Android 每次文件选择都在 UUID 目录生成新副本；普通选择入口没有 previousId，LocalVideo 又以副本 canonicalPath 派生身份，同一文档重新选择会新建身份并丢失续播。补充探针以两份相同内容/名称的不同缓存路径验证了身份不同、第二次进度为 0；Android 文档选择全链路仍待设备验证。
- 待修复：Windows 数据目录锁解决新版本多进程争用，但文件关联参数没有转发。应用已运行时双击其他视频只打开提示窗口，不能在现有播放器直接打开该文件；这是公开说明过的功能欠缺，不能将其视为文件关联全链路验收完成。
- 待修复：下载选集横屏已修，但 LocalVideoPage 仍为不可滚动 Column；568×320、顶部 AppBar 56 和底部栏 64 的布局探针底部溢出 80px。
- 交付物待同步：此前提供的 `build/local-video-installer-20261031105627/zero-player-0.0.8-windows-x64-setup.exe` SHA256 仍为 `49799BE639065FCA9CC20EDD2A920D4CE6317A2BAF29FFD0D49261108C013D23`，修改时间 11:07:30；新 Release EXE 修改时间 13:18:31。旧安装器没有包含本轮修复，不能用旧安装器验证新源码。
- 下载“目标已发布但数据库尚未提交”崩溃窗口仍按保守拒绝同名文件处理（上节已注明），属于尚未自动恢复的边界。Android/TV 实机及安装后关联/卸载仍未验收；修复会话曾误触实际用户数据目录的探针记录保留，不声称其完全隔离或无影响。

## 指定下载目录、本地视频与播放器补齐（2026-10-31）

- 开始前工作区干净，已创建本地备份检查点 `7eb0bb7`（父提交 `2f16bfe`）；未推送。以下功能改动保留在工作区，尚未公开发布。
- 下载选集增加保存目录；Windows 使用文件夹选择，Android 使用 SAF 持久目录授权。目标与任务在同一事务保存，下载完成后自动重封装 MP4；已有任务可重新选择目录。保存失败保留完整缓存，重试不重新联网下载；缓存仍可离线播放/导出。目录中已有同名文件不覆盖，删除任务保留用户目录中的视频。保存过程支持取消，Windows 临时文件写完后发布，Android 取消/失败清理本次新建文档。
- 新增“本地视频”菜单，支持常见单文件视频、续播与观看记录/首页继续观看；Windows 接受文件路径启动参数。通过受控离线服务器只暴露所选文件，支持 Range；不开放相邻文件、外部播放列表、脚本或自动加载字幕。Android 视频选择采用专用流式复制桥接，避免现有文件选择插件将整段视频装入内存；系统清除缓存或原文件移动后需重新选择。
- 播放器设置增加内嵌音轨/字幕选择，补充本地播放错误提示，并修复离线流程原先跳过本地视频进度保存的问题。修复导出器将 HLS 专用 allowed_extensions 参数用于普通 MP4 导致导出失败的问题。
- Windows 安装器提供默认不勾选的格式关联任务，注册当前用户的 OpenWithProgids / Capabilities，并在完成页提供默认应用设置入口。默认播放器由用户在 Windows 系统中确认，便携版不写关联。监管、过滤和网络边界保留；监管下无可验证来源的本地文件会被阻止。
- 全量单元/组件回归 534 项通过、2 项按原配置跳过：`build/local-video-final-tests-verified.log`。12 项 Python 工具回归通过：`build/local-video-python-tests.log`。新增回归覆盖本地 Range、相邻文件隔离、关闭撤销、续播、标题过滤、目标文件保护、保存失败后缓存重试及删除保留外部文件。
- Windows 原生 2 项业务用例通过（不计 tearDownAll）：完整 HLS 下载到指定目录、FFmpeg 重封装和完整性校验；本地视频实际解码、跳转、进度保存和导出后重新播放。最终日志 `.dart_tool/native-b93af50c/local_video_native_test.log`。驱动仍有既有插件检测提示，业务结果与退出码均成功。
- 保留早期失败证据：`.dart_tool/native-a499d7bd/`（本地进度未保存）、`.dart_tool/native-c330d23c/`（MP4 不接受 HLS 参数）；`build/local-video-final-tests.log`（任务元数据错误触发来源观察者、异步文件打开异常）。已修复后复验，上述失败不能当成功证据。
- 最终相关回归 8 项通过（`build/local-video-final-targeted.log`），静态分析无问题（`build/local-video-final-analyze-verified.log`），源码/函数规模检查通过。Android ARM64 Debug 构建通过（`build/local-video-android-final.log`），APK ZIP CRC 完整且只含 arm64-v8a；旧调试包已保留为 `app-debug-before-local-video-*.apk`。当前 `build/app/outputs/flutter-apk/app-debug.apk` 是普通调试包，非签名发行版。
- Windows x64 最终普通 Release 构建通过（`build/local-video-windows-final-verified.log`）；产物 `build/windows/x64/runner/Release/zero_player.exe` 需保留同目录 DLL/data。普通插件注册中无 integration_test。安装器最终编译通过（`build/local-video-installer-final.log`），本地测试包 `build/local-video-installer-20261031105627/zero-player-0.0.8-windows-x64-setup.exe`；APK/安装器校验和在 `build/local-video-artifacts-sha256.txt`。本轮未公开发布或修改用户默认应用。
- Android/TV 实机、真实用户媒体长时播放、安装后关联及卸载行为未验收；安装器仅做编译检查，未安装到用户系统。

## 全模块代码与交互审查（2026-10-31，历史待修复清单）

- 审查当前工作区（含上轮尚未提交的功能改动）；统计 lib 下 293 个 Dart 文件、37,586 行。检查各业务模块入口、下载/播放状态机、Windows/Android 桥接、历史与备份、监管边界及关键服务组合。本轮未修改业务源码，未安装到用户系统。
- 本轮全量单元/组件回归 534 项通过、2 项按原配置跳过（`build/module-review-regression.log`）。另外在忽略目录 `build/module_review_probe_test.dart` 编写 6 项隔离探针，全部命中预期异常（`build/module-review-probes-final.log`）；探针通过表示成功复现缺陷，不表示对应功能正常。
- 探针确认：①缓存已标 complete、目标尚未保存的任务不参加启动恢复；②崩溃遗留 output.mp4 令首次保存重试失败（finally 清理后可再次重试）；③首页按 id 打开已失效本地记录后，“选择视频文件”仍反复尝试旧路径；④Windows 小窗退出播放页后未恢复置顶/窗口状态；⑤已就绪本地/离线视频仍显示特征标记操作，但 markTarget 一律拒绝；⑥568×320 横屏下载弹窗底部溢出 116 像素。
- 代码链路还确认：首页继续观看只在初始化/完整刷新时更新 Future，未订阅 watch_history 或路由返回，播放返回后可能显示旧记录；Android 本地选择缓存缺少应用内配额、清理、复制取消和进度。
- 高优先级风险（静态链路，未制造真实数据损坏）：Windows 没有单实例/参数转发或共享缓存所有权锁；多个进程使用同一应用数据目录，第二进程启动会执行 recover 和缓存 .part 清理。文件关联增加此路径的触发机会，需要隔离环境验证并补进程协调。
- 组织改善建议：以媒体类型/能力表达本地、下载、在线、直播的操作边界；将 PlaybackController 的选线恢复、特征采集/标记和进度存储按职责解耦；把本地记录 SQL 从界面抽到仓库，细化 app_meta 的领域变更通知，避免历史写入触发无关源列表刷新。现有文件规模没有超过项目上限，无需机械拆文件。
- 下一步建议顺序：进程/缓存所有权与下载保存恢复 → 本地能力/失效重选/弹窗布局/小窗清理 → 首页历史订阅和 Android 资源管理 → Android/TV 真机、安装/卸载关联、长时播放验证。以上问题本轮仅审查记录，尚未修复。

## 播放器电视焦点与弹窗修复（2026-10-31）

- 电视设备或大屏显示模式下，方向键从播放画面进入控件；控件隐藏时方向键或确认键先唤醒，锁定后可通过遥控器聚焦解锁。焦点位于进度、音量滑块时，左右调整数值，上下切换控件。桌面普通模式保留方向键快捷操作和通过 Tab 返回画面的能力；手机横屏不继承大屏方向键行为。
- 控件间切换时根据真实焦点路径保持控件可见；设置等弹窗显示时，播放控件的隐藏定时器不抢走弹窗输入焦点。原生测试辅助器只将已注册的网关媒体资源加入信任判断，生产网络及媒体限制未变。
- 全量单元/界面回归 529 项通过、2 项按既有配置跳过，日志 `build/tv-focus-20261031-complete-tests.log`；测试按职责拆分后相关回归 16 项通过。发布工具 Python 回归 12 项通过，源码/函数规模检查和最终静态分析通过（`build/tv-focus-20261031-final-analyze.log`）。
- Windows 原生 1 项业务用例通过：合成 MP4 实际解码期间，模拟确认/方向键唤醒控件、进入设置并离开进度条；日志 `.dart_tool/native-e17f3d00/tv_playback_focus_test.log`。驱动仍有既有插件检测提示，业务用例与进程退出码均为成功。早期失败日志分别保留于 `.dart_tool/native-98abe285/`（测试辅助器未登记媒体资源）和 `.dart_tool/native-c15f5770/`（Windows 不支持模拟 Select，改用 Enter；Select 已由组件测试覆盖）。
- Windows x64 普通 Release 构建通过，`build/windows/x64/runner/Release/zero_player.exe` 需保留同目录 DLL/data；日志 `build/tv-focus-20261031-windows.log`，普通插件注册无 integration_test。Android/TV 实机、硬件遥控器和真实用户媒体仍未验收。
- Android ARM64 Debug 编译通过（`build/tv-focus-20261031-android.log`）；包体只含 arm64-v8a，Flutter/mpv 原生库、资源清单、ZIP CRC 和 v2 签名检查通过。`build/app/outputs/flutter-apk/app-debug.apk` 为普通调试包，包名 `dev.zeroplayer.zero_player`、版本 `0.0.8+8`，本轮未安装；不能与之前独立包名的测试 Release 混淆。恢复阶段原调试包已备份至同目录 `app-debug-before-tv-focus-20261031.apk`，SHA-256 仍为 `f868082b7a3541a27077a4b8bac0d170c1c22642fb63487dd41858938f8b46e2`。

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

本轮追加验证：解析与版本定向回归 8 项通过，试听畸形格式回归通过；静态分析无问题。Windows 原生安全与离线音乐各 1 项业务用例通过（不计 tearDownAll），证据 .dart_tool/native-ad5d5d9a/。普通 Windows Release 构建通过，最终打包前重新构建恢复插件注册。
