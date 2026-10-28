# 渠道整理与发现页改进（2026-10-28）

> 本文保留本日早期阶段记录。后续用户已确认自动启停策略；最终核查数量、策略和打包提交结果以 [v0.0.2 验收记录](HARDENING-2026-10-28.md) 为准。

## 范围与实现

基于本会话已完成的两类 MaccmsResources 导入、点播/直播探活清理、CCTV 别名归组、广播成功快照、收藏与 Windows 托盘播放，继续完成渠道整理、收藏、详情和发现页内容调整。

- SourceConnectivity 独立提供 DNS 与 TCP 诊断，支持测试注入。本机解析失败不能单独证明域名消失；只有 Google 与 Cloudflare DoH 同时返回与查询名匹配的 NXDOMAIN 才确认移除。
- SourceDiagnosticsStore 保存诊断与显式维护策略，SourceCuration 根据身份应用核查快照，较新的本地诊断优先。普通探测不自动批量删除，清理仍由用户确认执行。
- SourcePreferences 保存独立收藏偏好；默认收藏使用幂等初始化，保留取消选择。渠道合并迁移收藏、诊断；备份支持收藏并校验值。
- 通过接口站名、站点元数据、标题补全名称，保留手动名称。卡片提供星标与可能失效标签，首页及默认频道列表收藏优先。
- 详情包含网址、端口、IP、DNS 耗时、TCP Ping、实际请求方法、状态码及请求/响应头。仅探测时记录有界追踪，常见凭证字段脱敏。TCP Ping 不是 ICMP，也不等于播放质量。

## 本次渠道整理

使用项目实际 provider/parser 和网络客户端执行 tool/audit_sources.dart，合并内置与当前已有渠道后共 124 个：

| 结果 | 数量 | 处理 |
| --- | ---: | --- |
| 接口可用 | 31 | 不强制覆盖手动启停 |
| 明确失效 | 19 | 默认停用 |
| 结果不确定 | 74 | 标记可能失效，保留已有启停 |
| 双 DNS 确认域名不存在 | 0 | 本轮没有移除域名 |

本次得到非域名/网址名称 58 个。看剧AI、555电影、360资源站均在本次接口核查中成功，并写入默认收藏。

实际用户数据库已从 76 个渠道合并到 124 个：74 启用、50 停用（包括原停用与成人渠道），0 移除。不确定的已有渠道启停选择全部保留；历史、下载、直播等其他数据表计数不变，SQLite 完整性检查为 ok。

应用前已通过 SQLite backup API 保存一致性备份：artifacts/user-backups/sources-before-curation-20261028-5e0a1d7a.sqlite。

内置核查快照：assets/source_audit.json；本轮完整报告：artifacts/source-audit-2026-10-28.json；原始执行日志：build/source-audit.log。这些结果仅反映核查时的本机网络环境，不能作为普遍可用率或媒体完整播放保证。

## 发现页数据源评估

已移除 Bangumi、影视榜单及其请求逻辑；旧设置值在加载时保存为豆瓣，避免遗留设置影响备份。

实测候选公开页面：

| 页面 | 本次响应 | 选择 |
| --- | --- | --- |
| https://movie.douban.com/coming | HTTP 200，24,273 字节；解析出 20 条 | 采用上映日历，结构明确，复用网络栈 |
| https://www.1905.com/news/ | HTTP 200，521,385 字节 | 暂不引入新闻抓取，维护面更大 |

日历保留来源日期精度、公开档期与豆瓣条目链接，不把重映误称为新片，不承诺上映即能播放。成功缓存六小时；网络或解析失败回退上次成功列表，不覆盖成功时间戳。公开页面结构或限流仍可能变化。

## 验证记录

- 静态分析：flutter analyze --no-pub 通过，无问题。
- 文件/函数规模检查通过（源码 ≤1500 行，函数 ≤100 行）。
- 单元与组件测试：231 通过，2 个显式公网用例跳过。
- 实页日历解析：20 条，保留从 10 月 30 日至 2027 年 03 月 08 日的来源日期文本。
- Windows 原生回归：home_discovery_test.dart 共 2 项通过，覆盖分页、聚合、刷新、窗口布局、收藏即时排序、渠道详情及日历缓存入口。日志位于 build/source-curation-native.log。
- 视觉检查：已检查 artifacts/source-curation-phone.png、source-curation-details.png、source-release-calendar.png；窄屏卡片和宽屏详情无溢出。
- Windows Release 构建成功：flutter build windows --release --no-pub；日志位于 build/source-curation-release.log。程序为 build/windows/x64/runner/Release/zero_player.exe，须保留同目录运行库和 data 文件夹。

本轮未覆盖正在运行的旧发行目录，未关闭用户应用，也未创建 Git 提交。
