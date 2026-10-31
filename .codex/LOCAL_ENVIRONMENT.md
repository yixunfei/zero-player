# 本机开发环境（2026-10-30）

本文件为本机说明，不替代项目技术契约或发布门禁。跨机器优先通过 PATH、环境变量和项目脚本定位工具，历史日志里的盘符不是当前默认值。

- 当前工作区：`K:\zero-player`。原项目盘 L: 已改为 K:，原 Docker/备份盘 M: 已改为 L:。
- Docker 服务资源根：L:/docker_space；当前引擎数据：L:/docker_space/desktop-20261030。本机 context 为 desktop-linux，不批量启动旧业务服务。
- GRADLE_USER_HOME=E:/gradle-cache；Maven 本地仓库 D:/mvn_rep。工具与镜像配置是本机设置，不写死到业务源代码。
- Flutter 3.44.1 / Dart 3.12.1；JAVA_HOME 使用 JDK21，要求 Java17 的 Gradle 模块使用独立 MicrosoftJDK17 工具链。
- Git Perl 标准 site_perl 已补齐依赖；Rust 按项目 rust-toolchain.toml 定位，libclang 通过环境变量定位。无需复制旧的 C 盘缓存或临时 wrapper。
- 恢复阶段已实际构建 Android ARM64 debug APK；本轮 SHA-256 复核一致，详见 docs/implementation/STATUS.md。Windows 原生 3 项回归及普通 Release 已在本轮另行验证通过；Android Release 签名和设备验收不在本轮结论内。
- 本轮 doctor 验证 Android 许可及 VS 2022 17.14.44 / Windows SDK 10.0.26100.0 可用；没有连接 Android 设备。Flutter doctor 仍报告 SDK upstream 为 unknown source，但 Git origin 为官方 Flutter 仓库，本轮未修改 SDK 或屏蔽提示。
- Windows 旧 CMake 缓存绑定原 L:，已原位保留为 build/windows-before-restore-20261030；原生测试使用 tool/run_windows_native.ps1，不能复用旧缓存。

## 当前入口

- `README.md`
- `docs/implementation/BUILD.md`

## 清理与恢复

保留源素材、未提交改动、计划/评审证据、签名材料及业务数据。无引用的临时日志由本轮清理清单记录并可回退；不要清空整个 .r 或 .tmp-evidence，这些目录可能仍含有效原生依赖和测试证据。

跨项目恢复与验收记录：C:/Users/yixun/Documents/Codex/2026-10-30/da/outputs/恢复状态.md。
