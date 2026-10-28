# Zero Player v0.0.6

2026-10-28（Asia/Shanghai）· Windows x64 阶段性正式版本，构建号 0.0.6+6。

## 相对上个公开版本

- 汇总 v0.0.2–v0.0.5 的窗口退出修复、播放与网络加固、频道诊断和整理、优先来源搜索等改进。
- 广播支持离开页面继续播放、迷你控制栏及 Windows 托盘收听。
- 监管模式覆盖点播、直播和广播，敏感操作逐次验证；开启监管强制成人过滤，并清除受限来源的节目展示与网址信息。

## 本次检查修复

- 离线文件服务在超大 Range 数字或空文件范围请求下会抛出异常并返回 500。现按文件大小安全截断末尾/后缀范围，不可满足的范围返回 416 并包含文件大小。
- 源码 ZIP 原先只从 Git index 取文件名、实际却读工作区内容，可能包含未暂存修改或与暂存版本不一致。现固定 index tree，并直接归档对应 blob；版本号也来自同一快照，写入失败不会覆盖原归档。
- 打包脚本原先可把旧 Windows 二进制标为新版本。现先核对完整产品版本，并提前检查源码归档、原生来源清单和 staging 状态。
- 更新 README 中滞后的版本及下载说明，明确当前 Windows 与旧 Android 包的范围。

## 验证记录

- flutter analyze --no-pub 无问题；Dart 源码文件/函数规模检查通过。
- 全量单元与组件测试：325 项通过，2 项须显式启用的公网测试按原有条件跳过。
- 新增 10 项本地文件 Range 回归、4 项真实 Git index 归档回归；修复前分别复现 6 项失败和 3 项失败，修复后全部通过。
- Windows 原生测试：窗口壳 2 项、广播托盘 1 项、产品流程/离线导出 2 项通过。测试使用隔离临时数据库和本地合成媒体。
- 已实际验证旧版本 Windows 二进制被打包前置校验拒绝，不会创建新版 staging。
- Windows Release 0.0.6+6 构建成功；安装器与便携包共 269 个分发文件逐项 SHA-256 对照 staging 一致，安装后的产品版本为 0.0.6+6。独立目录静默安装和卸载通过，测试登记已清除。
- 源码 ZIP 的 436 个文件逐项验证与暂存 Git blob 精确一致；发行附件提供 SHA256SUMS.txt。

## 发布文件

- zero-player-0.0.6-windows-x64-setup.exe：Windows 安装器。
- zero-player-0.0.6-windows-x64-portable.zip：完整解压后运行 zero_player.exe。
- zero-player-0.0.6-source.zip：对应 Git index 快照的源码。
- zero-player-0.0.6-third-party-notices.zip、zero-player-0.0.6-native-sources.zip：第三方声明和原生来源材料。
- SHA256SUMS.txt：分发文件 SHA-256 校验和。

## 范围与限制

本次仅构建和验证 Windows x64，不发布新的 Android 包。Android 旧包仍保留在 v0.0.1。广播仍为实验功能；公开来源可用性随网络和源站变化。Windows 二进制未做商业 Authenticode 签名。监管依据来源及文本元数据，不分析视频画面，也不替代操作系统账户权限。
