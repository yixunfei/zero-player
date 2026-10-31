# 项目工作入口

- 面向 Windows、Android/TV 的 Flutter 播放器；没有必需的业务后端。开发、原生测试与发行入口见 README.md 和 docs/implementation/BUILD.md。
- Flutter 平台测试和构建串行执行，保留插件注册文件中的已有改动。原生依赖按既有摘要校验，不替换为系统中任意版本的 DLL。
- 监管、内容过滤、网络访问策略及恢复码边界不能因构建或清理而削弱。设备或真实媒体未验证时明确记录。

- 本机路径、工具与清理约定见 [.codex/LOCAL_ENVIRONMENT.md](.codex/LOCAL_ENVIRONMENT.md)。
- 进度使用项目已有权威入口；不复制整段旧聊天或建立并行的“当前状态”文件。保留工作区已有改动。
