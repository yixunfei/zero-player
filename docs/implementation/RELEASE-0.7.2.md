# v0.7.2

应用版本为 `0.7.2+72`。发行目标为 Windows x64 安装器和便携包、Android ARM64 开发测试 APK。

- 网易云歌单按公开曲目 ID 补齐，保留原顺序，最多 500 首。
- 歌单播放、连播和预检下一首均通过歌曲搜索匹配音源。点击播放条歌名打开完整同步歌词。
- Windows 播放条减少进度更新造成的界面和无障碍树变化，以缓解已定位到 Flutter Windows 无障碍桥的原生闪退。

Windows 原生播放已通过短时回归，仍记录无障碍树告警。Windows 原场景长时播放与 Android/TV 实机待验收。Android APK 使用开发测试签名和独立包名 `dev.zeroplayer.zero_player.devtest`。详见[实施状态](STATUS.md)。
