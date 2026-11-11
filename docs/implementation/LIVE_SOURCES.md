# 内置直播源清单与维护

2026-11-11 的随包目录包含 16 份启用订阅。合并同台后有 119 个频道、120 条唯一线路，其中 12 个频道归入「体育直播」。表内按订阅统计，同一频道可有多个来源。

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
| qist/tvbox · 地方电视精选 | 5 | 5 | [订阅](https://raw.githubusercontent.com/qist/tvbox/refs/heads/master/tvboxtv.txt) · [配置入口](https://github.com/qist/tvbox) |
| 拾光 · 地方电视精选 | 9 | 9 | [订阅](https://raw.githubusercontent.com/xmbjm/svip/refs/heads/main/FM.json) · [配置入口](https://github.com/xmbjm/svip) |

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

## 2026-11-11 补充来源核对

对本轮 22 个入口及其公开配置引用作实际请求。网页只提取其公布的配置地址。通过代理和 GitHub 原始文件提供的同一配置合并核对。直播新候选中抽测 250 条去重线路，93 条取得媒体响应，87 条进入 20 秒连续解码，61 条首轮通过，其中 58 条通过第二轮。选入拾光的 9 个、qist 的 5 个地方台，每条还对照了台标或节目画面。电影错标、同台镜像、旧隔离线路、时效地址和不稳定线路均排除。

从可识别的点播接口去重后复查 8 个缺项。天涯资源在两种协议下都能解析并连续解码 3 部作品，但三部作品的抽查画面均有博彩推广水印，已排除。建安能浏览目录，未能确认直连播放。其余候选未通过接口复查，本轮没有新增点播。结果来自本轮取样，Android / TV 真机及长时间播放另行验收。

| 序号 | 输入入口 | 直播 | 点播 |
| ---: | --- | --- | --- |
| 1 | FongMi / 菜妮丝 | 下载页指向同域配置，复请求取得 JSON，无直播项 | 直连非凡是已处理来源，其余依赖脚本 |
| 2 | 极狐 `ymshaoer` | 解析到少儿列表，子列表返回 401 | 无直连接口 |
| 3 | 俊佬 `top98.json` | 旧轮已解析，本次直播子列表返回 404 | 无支持的直连接口 |
| 4 | 小盒子 `/xhz` | 旧轮已处理，对应已内置的小盒子直播列表 | 影视条目依赖脚本 |
| 5 | 影视仓 `eggp/0211/tv.json` | 可识别直播与第 13 项重合，复测无新增 | 非凡镜像，已处理 |
| 6 | 欧歌 `tv.nxog.top/m/111.php` | TLS 验证失败 | 同一入口无法验证 |
| 7 | 影视仓 / OK 影视分发页 | 从网页提取 4 个配置入口，能解析的配置重复第 13 项 | 非凡镜像，已处理 |
| 8 | 饭太硬导航 `fty.888484.xyz/tv` | 从网页提取 6 个入口，主配置与第 18 项重复 | 可取到的配置未提供新增直连接口 |
| 9 | 游魂 `/tv/wex` | APTV 镜像与已内置来源重复，另一列表无可入选直连 | 无直连接口 |
| 10 | `raw.liucn.cc/box/m.json` | 现有老刘直播订阅已收录，肥猫和 IPv6 子列表返回 404 | 与第 16 项一起去重，缺项未通过复查 |
| 11 | `tv.203511.xyz/0821.json` | 子列表连接失败或为 MV、已有直播入口 | 暴风、索尼、360 均已处理 |
| 12 | `124.223.214.31:8/api.json` | 无可识别直连 | 无支持的直连接口 |
| 13 | 影视仓 `vip/vip/tv.json` | 平台直播返回非列表，港澳台列表连接失败，旧影仓精选仍隔离 | 非凡镜像，已处理 |
| 14 | `47.96.82.41:5188/api.json` | 无可识别直连 | 配置依赖脚本 |
| 15 | ph7368 Gist `gistfile1.txt` | 配置可解析，无可识别直连 | 无支持的直连接口 |
| 16 | `liu673cn/box@main/m.json` | 第 10 项镜像。另解析到老刘直播列表的 CDN 地址，未新增 | 与第 10 项配置相同 |
| 17 | `6800.kstore.vip/fish.json` | 指向 TVBox 本机代理 | 配置依赖脚本 |
| 18 | 饭太硬 `www.xn--sss604efuw.net/tv` | 旧轮已解析。APTV 镜像和已淘汰的直播平台列表未收录 | 无支持的直连接口 |
| 19 | 拾光 `xmbjm/svip/svip.json` | 核对镜像及原仓库，从 FM 列表选入 9 个地方台 | 无直连接口 |
| 20 | qist `jsm.json` | 代理失败后核对原仓库，从 `tvboxtv.txt` 选入 5 个地方台 | 天涯资源因博彩推广水印排除 |
| 21 | qist `xiaosa/api.json` | 代理失败后核对原仓库，无可识别直连 | 配置依赖脚本 |
| 22 | `550.3vcn.work/wdjyys.json` | 直播子列表返回 404 | 可识别接口去重后无新候选通过 |

原始配置请求、候选去重、媒体解码及画面抽查记录保存在本地 `build/source-review-20261111/`。
