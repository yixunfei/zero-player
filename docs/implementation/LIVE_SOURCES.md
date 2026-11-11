# 内置直播源清单与维护

2026-11-11 的随包目录包含 14 份启用订阅。合并同台后有 105 个频道、106 条唯一线路，其中 12 个频道归入「体育直播」。表内按订阅统计，同一频道可有多个来源。

| 内置订阅 | 频道 | 线路 | 上游 |
| --- | ---: | ---: | --- |
| iptv-org · 中国电视精选 | 53 | 53 | [订阅](https://raw.githubusercontent.com/iptv-org/iptv/master/streams/cn.m3u) · [配置入口](https://github.com/iptv-org/iptv) |
| 分享 · 综合电视精选 | 5 | 5 | [订阅](https://cdn.jsdelivr.net/gh/Guovin/iptv-api@gd/output/result.m3u) · [配置入口](https://raw.githubusercontent.com/maoystv/6/main/000.json) |
| Kimentanm · 电视精选 | 2 | 2 | [订阅](https://down.nigx.cn/raw.githubusercontent.com/Kimentanm/aptv/master/m3u/iptv.m3u) · [配置入口](https://9280.kstore.vip/newwex.json) |
| 哈基米 · 地方频道精选 | 4 | 4 | [订阅](https://pan.29o.cn/down.php/aa846bceb7a1b4adb0385b1f61b192e8.txt) · [配置入口](https://17264.kstore.space/%E5%93%88%E5%9F%BA%E7%B1%B3.png) |
| 东篱 / 游魂 · 电视精选 | 2 | 2 | [订阅](https://www.iyouhun.com/tv/zb) · [配置入口](https://raw.githubusercontent.com/chitue/dongliTV/main/api.json) |
| 追剧资源 · 拾光多仓 · cluntop_test | 10 | 10 | [订阅](https://clun.top/lib/iptv_test.m3u) · [配置入口](http://xmbjm.fh4u.org/dc.txt) |
| 追剧资源 · 小马 · 手动不知何时更新 | 1 | 1 | [订阅](https://szyyds.cn/tv/live/x.txt) · [配置入口](https://szyyds.cn/tv/x.json) |
| imDazui · raw.githubusercontent.com | 1 | 1 | [订阅](https://raw.githubusercontent.com/imDazui/Tvlist-awesome-m3u-m3u8/master/m3u/%E5%8F%B0%E6%B9%BE%E9%A6%99%E6%B8%AF%E6%BE%B3%E9%97%A8202506.m3u) · [配置入口](https://github.com/imdazui/tvlist-awesome-m3u-m3u8) |
| iptv-org · 国际体育精选 | 12 | 12 | [订阅](https://iptv-org.github.io/iptv/categories/sports.m3u) · [配置入口](https://github.com/iptv-org/iptv) |
| Zoo.ink · urlzf.zone.id | 10 | 10 | [订阅](https://urlzf.zone.id/iptv-api/output/user_result.m3u) · [配置入口](https://zoo.ink/tvbox.html) |
| 直播电视 · live.zbds.top | 3 | 3 | [订阅](https://live.zbds.top/tv/iptv4.txt) · [列表入口](https://live.zbds.top/tv/iptv4.txt) |
| qist/tvbox · raw.githubusercontent.com | 1 | 1 | [订阅](https://raw.githubusercontent.com/qist/tvbox/master/tvlive.txt) · [配置入口](https://github.com/qist/tvbox) |
| Zoo.ink · xhztv.top | 1 | 1 | [订阅](http://xhztv.top/xhz/live.txt) · [配置入口](https://zoo.ink/tvbox.html) |
| Zoo.ink · raw.liucn.cc | 1 | 1 | [订阅](https://raw.liucn.cc/box/libs/tv/tvlive.txt) · [配置入口](https://zoo.ink/tvbox.html) |

## 停用和隔离

- 西西电视已按用户反馈下架。升级会停用旧订阅，原直连线路及浏览器入口均已移除。
- 「频道信息 → 停用此渠道」停用该频道在指定订阅中的线路，保留其余渠道。停用整个频道需要确认。停用条目可从「已停用」分组复检恢复。
- 「管理订阅 / EPG」可以停用整份订阅，停止其所有频道和自动刷新。
- 王二小新综合电视精选和从 Zoo.ink 发现的体育精选已从随包目录移除。旧安装会停用这两份具体订阅并显示隔离原因。Zoo.ink 的 TVBox 目录及其他独立订阅仍可使用。已复现问题的媒体端点为 `173.208.212.130:8181` 和 `207.56.13.146:81`。收录时应排除其经其他列表转载的线路。
- 同轮取样中，浙江卫视、CCTV-14 与风云足球抽取的 40 个视频帧完全一致。另一轮也发现不同名称间有相同的 40 帧。抽样证据保存在本地 `build/live-integrity-20261111/frames.jsonl`。

- 其余 117 条线路逐一对照视频帧。撤出分享地方电视补充中把浙江新闻标成内蒙古卫视的订阅条目，移除哈基米中把余姚线路标成浙江钱江都市的条目，合并开化、兰溪与象山的重复线路。影仓精选的三条央视线路带时效参数，两轮复测均失败，已撤出随包目录。复测通过的内蒙古卫视和 Canal+ Sport 7 SK 保留。保留的 108 条线路均完成本轮 20 秒取样。

## 更新流程

1. 从上游读取 M3U、TXT、TVBox 或站点配置。核对发布方和列表出处，跳过已经隔离、上游注明失效、需要执行远程脚本或带有短期令牌的候选。awesome-zhuiju-free 仅通过手动同步检查。
2. 用应用的媒体网关发起实际请求。每条候选至少两次独立解码，每次约 20 秒，记录首段耗时及错误。对新增发布方和同一服务批量提供的频道对照台标、节目或官方排期，再抽样比对不同频道的画面。排除统一广告、录播、跨频道重复内容和解码不稳定的线路。
3. 按频道身份合并别名，清理重复地址。备用线路尽量选择不同服务。更新 [内置订阅目录](../../assets/live_candidates.json)、[快照](../../assets/catalogs/live/builtin.snapshots.json)、[订阅预检](../../assets/live_precheck.json) 和 [频道审计](../../assets/live_channel_audit.json)。更改已有精选时提高对应快照的 `revision`，保留用户已停用的频道。解除隔离时需在升级迁移中清理对应标记，并保留旧设备的停用状态。隔离记录在目录的 `quarantined` 中。
4. 核对本表与实际打包内容，验证旧数据库迁移、来源停用和正常播放。Windows 构建和 Android / TV 验收入口见 [BUILD.md](BUILD.md)。
