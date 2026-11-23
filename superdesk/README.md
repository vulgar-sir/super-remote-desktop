# super远程桌面（SuperDesk）

基于 [RustDesk](https://github.com/rustdesk/rustdesk) 1.5.3 二次开发的公司内部远程桌面：服务器自建、
客户端内置服务器配置装好即用，并带一套自研管理后台“super控制台”。

## 功能总览

| # | 功能 | 说明 | 实现位置 |
|---|---|---|---|
| — | 远程控制全家桶 | 远程控制、文件传输、剪贴板、聊天、语音、远程终端、端口转发、隐私模式、2FA 等（RustDesk 自带） | 客户端 |
| 1 | 双版本客户端 | **完整版**（IT 用，可控制别人）+ **员工助手**（只能被控，界面精简，设置全部锁定） | `superdesk/flavors.json` |
| 2 | 下载中心 | `/download/`：最新安装包、Android 扫码下载、批量部署说明 | `superdesk/scripts/publish.py` |
| 3 | 批量部署 | 一条命令：静默安装为开机服务 + 固定密码 + 上报电脑名/ID | `superdesk/deploy/` |
| 4 | 中继带宽治理 | 客户端默认均衡画质 25 帧；中继（P2P 打不通时才用）总带宽/单会话限速，拥堵时自动降速 | `.env` `RELAY_*` |
| 5 | super控制台 | `/admin/`：设备（在线状态/系统信息/强制断开）、账号、共享通讯录、设备分组、审计日志、公告 | `superdesk/console/` |
| 6 | 群通知 + 一键求助 | 员工端“请求 IT 协助”按钮；求助/连接/部署/文件传输/安全告警推送到企业微信/钉钉/飞书群 | 控制台 → 通知与设置 |
| 7 | 自有升级通道 | 客户端启动时检查服务器上的新版本，提示下载（不再提示官方 RustDesk 更新） | `flutter/lib/superdesk/` |
| 8 | 录屏归档 | 按分组开启：被控会话自动录屏并上传控制台，可在线播放/下载，按天数自动清理 | 控制台 → 会话录屏 |
| 9 | 访问策略 | 按分组：仅工作时间可连、仅公司账号电脑可连、必须被控端点击接受、附加任意 RustDesk 配置；随心跳 ~15 秒内生效 | 控制台 → 分组与访问策略 |
| 10 | P2P 直连 | WebRTC 打洞：只用现有的一个端口做信令，画面/键鼠在两台设备间直传，不占服务器带宽；打不通自动走中继 | hbbs 补丁 + `enable-webrtc` |

## 客户端界面

布局、文案和交互流程对齐 **UU远程**（按其桌面版 4.48 与手机版宣传图逐页对照），品牌、Logo 与图标为自有素材；
只改界面，RustDesk 原有功能全部保留：

- **Windows 完整版**：48px 标题栏（Logo + 名称；右侧 无线副屏 / 消息中心 / 账号 / 菜单 | 最小化 / 关闭，六个图标为同一套细线图标，
  悬停浅灰圆角底、关闭悬停红底；菜单：下载中心、如何添加设备、关于、检查更新；账号：头像卡片 + 退出登录）；
  浅灰侧栏分组 **我的设备**（最近 6 台，带在线绿点）/ **全部设备** / **远程协助**（开始协助、收藏设备）/ **设置**；
  - **远程协助**：“本设备”卡片（允许他人远程协助开关、本设备ID、验证方式下拉、验证码查看/刷新、复制并分享）
    + “远控伙伴设备”卡片（伙伴的设备ID + 连接）；
  - **全部设备**：按“电脑 / 手机/平板”分组（含本机），点 › 进设备页；**收藏设备**：空状态 + 添加收藏设备；
  - **同账号设备**：各设备登录同一控制台账号后自动互相出现在“我的设备 / 全部设备”（手机端“设备”页），无需连接过或收藏；
    数据来自控制台 `/api/peers`（按账号名匹配），客户端每 60 秒刷新一次，手机端下拉也会刷新；
  - 设备列表合并顺序：收藏 → 同账号设备 → 通讯录 → 最近连接（按 ID 去重）；
  - **同账号免密**：连接登录同一账号的设备时不用输验证码（设置 → 安全 →“允许同账号控制本设备”，默认开启；
    被控端设为“本机点击接受”时仍需点击）。见下文“同账号免密”；
  - **设备页**：在线/离线胶囊 + 名称 + ⋮（备注名、收藏、复制ID、删除记录），预览卡“进入桌面 →”，
    动作栏 文件传输 / 观看模式 / 终端 / 端口映射 / 更多（远程摄像头、RDP、复制ID）；“观看模式”连接后自动打开仅观看，“进入桌面”恢复完全控制；
  - **设置**：对齐 UU——常规 / 安全 / 网络 三个标签，每项一张卡片（图标 + 标题 + 灰色说明 + 开关/下拉/按钮）：
    外观、防止休眠、自动录制、软件更新；允许他人远程协助、连接方式与验证码、文件互传、被控权限、客户端锁定、IP 白名单；
    服务器状态、局域网发现、直接 IP 访问、代理。每页底部“更多…设置”进入 RustDesk 原有完整设置（显示、账户、打印机、关于等）。
    安装版沿用 RustDesk 的锁定：修改安全/网络项前需管理员授权或解锁 PIN；
  - **本机被控中**：有设备正在远控本机时，侧栏顶部出现蓝色卡片“本机被控中 / 当前有 N 台设备正在控制此电脑”，点击切到被控窗口。
  - **快速启动**（Windows 设备）：设备页“快速启动”放固定的应用（应用管理可移除），点应用即连接并在对方电脑上打开；
    “添加”或远控工具栏的九宫格按钮列出对方开始菜单里的应用（带图标），点击即打开、点 ☆ 固定到设备页。
    对方只会打开自己开始菜单列表里的快捷方式，且要求本次连接有键鼠控制权；需要双方都是新版本，服务器不用升级。
  - **远控工具栏**：白色圆角工具栏 + 灰色扁平图标（悬停浅蓝、关闭红色），新增“快速启动”按钮。
  - **无线副屏**：在手机/平板/另一台电脑上打开 Windows 电脑的设备页 → 更多 → 无线副屏：连接后让对方插入一块虚拟显示器并只显示它，
    本机即成为它的扩展屏；最后一个远控断开时对方自动拔掉虚拟显示器。需对方为安装版（服务运行）且 Windows 10 2004+，否则提示并按普通远控连接。
    标题栏双框图标打开使用说明。
  - **远程开机**：离线设备的预览中间显示电源按钮，发送 RustDesk 的网络唤醒包（需同一局域网且对方开启网络唤醒）。
  - **端口映射窗口**：对齐 UU——设备名 + 状态、“映射列表”卡片 + 添加、表格（名称/本地端口/目标地址/目标端口/映射状态/操作“⋯”：复制本地地址、删除）；
    增删仍调用 RustDesk 原有的 session 接口；RDP 映射页保持原样。
  - **消息中心**：标题栏铃铛（未读红色数字），打开后是公告列表（公告消息 + 日期 + 未读红点、一键已读），点开看正文；公告在控制台“公告”页发布。
  - **设备预览用真实壁纸**：Windows 客户端启动时把本机桌面壁纸缩成 480px 上传到控制台（壁纸变了才重传），
    登录了控制台账号的客户端在设备页用它做预览图；没有壁纸或未登录时仍是渐变底。
  主窗口最小 940×660。登录为 **账号密码**（控制台账号），不做短信/微信登录；
  登录框下方“没有账号？注册账号”可自助注册（无需审核，注册后自动登录，得到的是普通账号）。
- **Windows 员工助手**：紧凑窗口——本设备ID + 验证码卡片、醒目的“请求 IT 协助”按钮、录屏提示、状态。
- **被控时（连接管理窗口）**：对齐 UU 的“本机被控中”——蓝色卡片显示计时、对方名称和 ID、远程控制/传输文件等类型、连接时长，底部“断开远控”；全局主色统一为 #3A7BFC（会话工具栏、文件传输、对话框等 RustDesk 原有页面也随之统一）。
- **Android**：底部 远程协助 / 设备 / 设置，页面大标题；“远控伙伴设备”卡片 →“输入设备验证码”弹窗 → 开始远控；
  “本设备”卡片（允许他人远程协助开关、设备ID、验证码、复制并分享）+ 原有连接管理与权限卡片；
  设备页（真实壁纸预览卡 + 文件传输 / 观看模式 / 终端 / 更多；离线时电源按钮远程开机；Windows 设备下方“快速启动”
  四列应用 + 应用管理 + 添加应用），远控底部栏九宫格按钮打开快速启动面板。
- 验证码默认 **6 位纯数字**（便于电话里报给对方，可在设置中修改），每次被远控后自动更换。
- 在线状态：单端口模式下 hbbs 原本只在 NAT 测试端口回答在线查询，补丁让它在 WebSocket 上也回答，设备列表才能显示在线。

代码集中在 `flutter/lib/superdesk/`（`theme.dart` 配色与组件、`desktop_home.dart` 桌面主界面、
`mobile_home.dart` 手机主界面、`devices.dart` 设备数据），对上游文件只有少量挂接改动（见文末改动表）。

## 架构

```
 Windows / Android 客户端 ─┐
 浏览器（管理员/员工）─────┤  唯一对外端口（nginx: superdesk-gateway）
                           ├─ /ws/id     → hbbs  :21118   ID 注册、发起连接、WebRTC 信令
                           ├─ /ws/relay  → hbbr  :21119   中继（P2P 打不通时的远程画面/键鼠，带宽限速）
                           ├─ /api/      → super控制台 :21120  RustDesk 兼容 API（心跳/通讯录/审计/录屏）+ 扩展
                           ├─ /admin/    → super控制台 管理后台
                           └─ /download/ → 下载中心（静态文件）
```

服务器是 NAT 虚拟机，只映射了一个 TCP 端口，所以客户端用 WebSocket 模式连服务器。远程会话优先走
**WebRTC P2P**：双方经这个端口交换 SDP/ICE 候选，再用 UDP 打洞直连（STUN 用国内可达的小米/B站/芒果TV
公共服务器），画面不经服务器；同一会话同时准备中继，P2P 2.5 秒内没打通就用中继。
中继时：服务器实测上行约 25 Mbit/s，1080p 会话约 2–5 Mbit/s，可同时支撑约 5–8 路中继会话。

> **hbbs 补丁**：开源版 hbbs 只接受 UDP 注册（TCP/WebSocket 注册是付费 Pro 功能，直接回 `NOT_SUPPORT`），
> 单端口模式下设备无法上线。`superdesk/server/hbbs/tcp-register.patch` 让设备可通过 WebSocket 注册：
> 连接保持为该设备的下行通道（服务器心跳 15 秒、keep_alive 30 秒），发往该设备的打洞/中继请求改走这条连接；
> WebSocket 连接以“真实 IP + 连接端口”区分，同一 NAT 后的多台设备互不冲突。
> 同一补丁加上 **WebRTC 信令转发**（开源版 hbbs 不认识这些字段，Pro 版才有）：把发起方的 SDP offer 带进
> `PunchHole`、被控方的 answer 带回发起方，并双向转发 trickle ICE 候选（`IceCandidate`）——发起方的打洞连接在
> 收到 answer 后保持打开，作为候选的下行通道。协议字段见 `proto-webrtc.patch`（hbb_common 子模块）。
> 镜像由 `deploy-server.py` 离线构建。

## 目录

| 路径 | 说明 |
|---|---|
| `superdesk/server/` | 服务端 docker-compose、nginx 网关、`.env.example` |
| `superdesk/console/` | super控制台（FastAPI + SQLite + 原生 JS 后台），`tests/smoke_test.py` 端到端测试 |
| `superdesk/flavors.json` | 两个客户端版本的名称与内置配置 |
| `superdesk/scripts/` | 工具链安装、桥接代码生成、Windows/Android 构建、发布、服务器 SSH、P2P 端口检测 |
| `superdesk/docker/` | Linux 构建镜像（Android + 桥接代码） |
| `superdesk/deploy/` | 公司电脑批量部署脚本模板（发布时填入服务器地址） |
| `superdesk/branding/make_icons.py` | 一键生成全部图标 |
| `flutter/lib/superdesk/` | 客户端界面扩展（升级检查、请求协助、录屏提示） |
| `src/superdesk.rs` | 客户端内置配置加载、录屏上传开关 |
| `secrets/`、`dist/` | **不进 git**：真实服务器配置、签名密钥、控制台初始密码 / 构建产物 |

## 敏感信息（均被 .gitignore 排除，切勿提交）

| 文件 | 内容 | 丢失后果 |
|---|---|---|
| `服务器地址----不准放入git仓库.txt` | SSH 登录、对外端口 | 脚本无法连服务器 |
| `secrets/superdesk.json` | 服务器地址、公钥、API 地址、p2p 开关 | 按 `superdesk/config.example.json` 重建 |
| `secrets/console-admin.txt` | 控制台初始管理员密码 | 可在服务器 `.env` 查看 |
| `secrets/android/` | Android 签名密钥 | **无法给已安装的 App 推送更新，必须备份** |
| 服务器 `/opt/superdesk/data/id_ed25519*` | 服务器密钥对 | 换密钥后所有客户端要重新编译 |
| 服务器 `/opt/superdesk/data/console/` | 控制台数据库、录屏 | 设备/审计/录屏数据丢失（建议定期备份） |

## 服务端运维

部署在服务器 `/opt/superdesk/`（与机器上 superbot 等服务互不影响）。

```bash
cd /opt/superdesk
docker compose ps                     # 状态：hbbs / hbbr / console / gateway
docker compose logs -f --tail 50 console
docker compose up -d --build          # 修改配置或更新控制台代码后
cat data/id_ed25519.pub               # 服务器公钥
```

- **一键部署/更新服务端**（本机执行）：`python superdesk/scripts/deploy-server.py`
  （打 hbbs 补丁 + `cargo vendor` 离线依赖、上传控制台与网关配置、`docker compose up -d --build`；
  服务器上的 `.env` 和 `data/` 保持不变）。只更新控制台：`--console-only`。
- 零散操作：`python superdesk/scripts/sdssh.py put|putdir|run ...`（读取被忽略的服务器地址文件，不打印密码）。
- 回归测试：`python superdesk/console/tests/smoke_test.py <API地址> admin <密码>`（按 RustDesk 客户端协议跑 60 项）、
  `python superdesk/console/tests/test_notify.py`（三种群机器人消息格式与签名）。
- 端到端测试（会在本机临时安装员工助手服务，结束后卸载）：`python superdesk/tests/e2e_windows.py`
  （部署脚本 → 固定密码无人值守连接 → **会话走 WebRTC P2P、服务器端口抓包 8 秒 < 100 KB** → 覆盖重装 →
  工作时间策略拦截 → 解除 → 卸载）。
- Android 界面检查：`python superdesk/tests/android_emu.py setup|start|install <apk>|shot <png>`
  （腾讯云镜像下载模拟器与 Android 14 x86_64 镜像，WHPX 加速，可直接运行 arm64 APK）。
- 中继限速：`.env` 中 `RELAY_TOTAL_MBPS`（约为服务器带宽 90%）、`RELAY_SINGLE_MBPS`、`RELAY_DOWNGRADED_MBPS`，改完 `docker compose up -d hbbr`。
- 控制台首个管理员来自 `.env` 的 `CONSOLE_ADMIN_USER/PASSWORD`（仅数据库为空时生效）。

## super控制台（`http://<服务器>:<端口>/admin/`）

- **设备**：所有装了客户端的电脑自动出现（心跳 15 秒），显示在线状态、系统、当前用户、版本；可设置名称/备注/分组、查看详情、**强制断开**正在进行的远程。
- **分组与访问策略**：先建分组再在“设备”里分组；策略随心跳自动下发。
  启用“仅公司账号电脑可连”前，确认 IT 的电脑已在客户端登录控制台账号，否则会把自己挡在外面。
- **控制台账号**：管理员可登录后台；普通账号用于在客户端登录，以使用共享通讯录和设备列表。
  客户端可自助注册普通账号（备注“客户端注册”，同一 IP 每分钟最多 3 次）；不需要时在 通知与设置 → 账号注册 关闭。
- **共享通讯录**：按部门整理设备并授权给账号（只读/读写/完全控制），出现在客户端“地址簿”。
- **审计**：连接（谁、何时、连了哪台、多久、备注）、文件传输、安全告警、会话录屏。
- **通知与设置**：添加企业微信/钉钉/飞书群机器人 Webhook，选择推送的事件；录屏/审计保留天数。
- **公告**：发布/删除公告，出现在客户端右上角铃铛（消息中心）。所有已登记设备可见，不要写密码等敏感信息。
- **设备壁纸**：存放在数据目录 `wallpapers/`，只有登录了控制台账号的客户端能读取；删除设备记录时一并删除。

## 构建与发布客户端

> 工具链与构建目录在 `D:\superdesk`（纯英文路径：项目路径含中文，Flutter/ffmpeg 会出错）。脚本用 `pwsh` 运行。

```powershell
pwsh superdesk\scripts\setup-windows-toolchain.ps1   # 一次性：Rust 1.75、LLVM 15、vcpkg、Flutter 3.24.5+定制引擎
pwsh superdesk\scripts\gen-bridge-windows.ps1        # 生成 Flutter↔Rust 桥接代码（改了 src/flutter_ffi.rs 才需重跑）
pwsh superdesk\scripts\build-windows.ps1             # → dist\SuperDesk-…-win-x64.exe、dist\SuperDeskHelper-…-win-x64.exe
pwsh superdesk\scripts\build-android.ps1             # Docker 中构建 → dist\SuperDesk-…-android-arm64-v8a.apk
python superdesk\scripts\publish.py --notes "本次更新说明"   # 上传到下载中心，客户端随后提示升级
```

- 同一批构建共用一个构建号（时间戳），客户端靠它判断是否有新版本。
- Windows 主程序按应用名命名（`SuperDesk.exe` / `SuperDeskHelper.exe`）：RustDesk 安装程序创建服务、快捷方式时
  使用“应用名.exe”，若仍叫 rustdesk.exe 会安装失败（服务建不起来）。
- Android 首次构建会生成签名密钥到 `secrets/android/`，**务必备份**。
- Docker 构建网络不稳时：脚本内置重试；`SUPERDESK_DOCKER_KEEP_PROXY=1` 可改走 Docker Desktop 代理。

## 部署到公司电脑

在目标电脑以管理员身份打开 PowerShell：

```powershell
iwr http://<服务器>:<端口>/download/deploy-superdesk.ps1 -OutFile $env:TEMP\d.ps1; & $env:TEMP\d.ps1 -Password "公司统一密码"
```

默认安装员工助手版（`-Flavor full` 安装完整版），注册为开机服务、设置固定密码，并上报到控制台“部署记录/设备”。
也可下载 `deploy-superdesk.bat` + `.ps1` 放同一目录双击运行，或用于组策略启动脚本（`deploy-superdesk.bat 密码`）。

## 同账号免密

两台设备登录同一个控制台账号后，互相连接不需要验证码（对齐 UU“允许同账号控制本设备”）：

1. 被控端在登录挑战（`Hash`）里标记 `sd_account_login`（开关开启、且不是“仅点击接受”模式时）；
2. 主控端已登录账号、且本次没有可用密码时，不弹密码框，而是向控制台申请票据
   `POST /api/superdesk/same-account/ticket`（Bearer 令牌）。控制台只在“令牌属于发起设备、目标设备当前登录的是同一账号”时
   签发，票据 60 秒有效、只能用一次，绑定发起设备和目标设备；
3. 票据放在 `LoginRequest.sd_account_ticket` 里发给被控端，被控端用 `POST /api/superdesk/same-account/verify` 向控制台核验
   （无论成败票据都会作废），通过即按密码正确处理（双重认证、ID 白名单、访问策略照常生效），控制台“操作记录”记一条；
   不通过则回“需要密码”，主控端照常弹出密码框，被控端照常可点击接受。

- 协议字段都在客户端的 `libs/base/protos/message.proto`（字段号 1001），服务器 hbbs 不用升级；新旧版本混用时自动走原来的密码流程。
- 关闭：被控端设置里关掉开关（选项 `superdesk-allow-same-account` = `N`），也可在控制台分组策略“附加 RustDesk 配置”里统一下发。
- 注意：账号即钥匙。在别人的电脑上登录自己的账号，等于让那台电脑和自己的设备互相免密；用完请退出登录。
  客户端退出登录时若连不上控制台，控制台仍会认为该设备属于此账号，可在控制台删除该设备记录。

## P2P 直连（第 10 项）

默认开启，无需额外端口：客户端内置 `enable-webrtc=Y` 与 `ice-servers`（STUN 列表，可在
`secrets/superdesk.json` 用 `"ice_servers"` 覆盖，或用 `"webrtc": false` 关闭），信令走现有单端口。

- 确认方式：客户端日志 `used to establish WebRTC connection`（中继则为 `WebSocket`）；`e2e_windows.py` 自动检查。
  实测（同一对客户端、各 10 秒）：P2P 时服务器端口仅 2 KB，关闭 WebRTC 走中继时 555 KB。
  Android 模拟器（新版 APK）双向实测：电脑控手机、手机控电脑均走 P2P，服务器端口 1–2 KB / 10 秒。
- 打不通的情况（自动退回中继，功能不受影响）：双方都在对称型 NAT 后（部分 4G/5G、严格的公司防火墙）、
  网络禁止 UDP、本机开了 SOCKS 代理，或 UDP 经 TUN 代理（Clash 等）出网。没有 TURN 服务器（NAT 虚拟机无法映射
  UDP），这些情况只能中继。
- Android 端（模拟器实测）只上报 STUN 得到的公网候选、不上报本机网卡地址，所以手机与电脑在同一局域网时，
  直连依赖路由器支持回环（hairpin），不支持则走中继。
- 刚断开就立即重连（几秒内）时偶尔走中继（上一个 P2P 会话还在收尾），会话照常可用。
- 信令走 `ws://`（服务器无域名证书，无 TLS），SDP/ICE 候选（含内网 IP）在客户端与服务器之间不加密；
  会话本身由 DTLS 加密，且与服务器签名的对端身份绑定。
- 可选：若服务商能把 **TCP 21115-21117 + UDP 21116** 按相同端口号映射，可跑 `check-p2p-ports.py` 确认后在
  `secrets/superdesk.json` 设 `"p2p": true` 改用 RustDesk 原生打洞（一般不需要）。

## 对 RustDesk 源码的改动（升级时需保留）

| 文件 | 改动 |
|---|---|
| `libs/hbb_common/src/config.rs` | `APP_NAME`、`RENDEZVOUS_SERVERS`、`RS_PUB_KEY` 改为编译期环境变量（`SUPERDESK_*`），源码不含服务器信息 |
| `libs/hbb_common/src/websocket.rs` | 纯 IP 服务器设置 `websocket-port` 时也走 `/ws/id`、`/ws/relay` 单端口网关 |
| `src/superdesk.rs`（新增）、`src/common.rs`、`src/lib.rs` | 启动时加载编译期内置配置（`SUPERDESK_CONFIG`，官方定制客户端格式，含 hard settings） |
| `src/hbbs_http/record_upload.rs` | 录屏上传开关可由控制台策略 `superdesk-record-upload` 打开（上游此开关无人设置） |
| `superdesk/server/hbbs/tcp-register.patch`、`proto-webrtc.patch`（服务端） | hbbs 支持 TCP/WebSocket 注册与 WebRTC 信令转发，见上文“hbbs 补丁” |
| `flutter/lib/superdesk/superdesk.dart`（新增）、`desktop_home_page.dart`、`mobile/pages/home_page.dart` | 升级检查、员工端“请求 IT 协助”、录屏提示、启动时上报版本 |
| `libs/base/protos/message.proto` | 新增 `SdQuickApps`（Misc 字段 1001），快速启动的请求/应用列表/启动；`Hash.sd_account_login`、`LoginRequest.sd_account_ticket`（同账号免密） |
| `src/server/connection.rs`（登录挑战标记 + 登录分支）、`src/client.rs`（`handle_hash` 申请票据、`create_login_msg` 附带票据） | 同账号免密的挂钩（逻辑在 `src/superdesk/same_account.rs`） |
| `src/server/connection.rs`、`src/client/io_loop.rs`、`src/ui_session_interface.rs` | 快速启动的三处挂钩：被控端应答、主控端转发给界面、`toggle_option` 发送命令（逻辑在 `src/superdesk/quick_apps.rs`） |
| `Cargo.toml` | winapi 加 `wingdi` 特性（读取快捷方式图标） |
| `flutter/lib/desktop/widgets/remote_toolbar.dart` | 工具栏 UU 风格（`_sdUuToolbar`）+ 快速启动按钮 |
| `flutter/lib/models/model.dart`、`flutter/lib/desktop/pages/remote_tab_page.dart` | 快速启动事件、连上后执行设备页的待办、接收主窗口的打开请求 |
| `flutter/lib/desktop/pages/port_forward_page.dart` | 非 RDP 的端口映射改用 `SdPortForwardView`（一行挂钩） |
| `flutter/lib/common/widgets/login.dart` | 登录框下方挂“注册账号”入口（`sdRegisterLink`，调用控制台 `/api/superdesk/register`） |
| `flutter/lib/superdesk/theme.dart`、`desktop_home.dart`、`mobile_home.dart`、`devices.dart`（新增） | 新界面（对齐 UU远程）：配色组件、桌面/手机主界面、设备数据 |
| `common.dart`（`MyTheme.accent` 改为 #3A7BFC）、`desktop/pages/server_page.dart`（被控卡片 `_sdUuCm`、断开远控按钮） | 被控窗口与全局主色 |
| `desktop_tab_page.dart`（`sdBarHeight`/`sdLeading`，完整版隐藏默认最小化/关闭改由 `sdTitleBarTail` 绘制）+ `tabbar_widget.dart`（`sdBarHeight`/`sdLeading`）、`desktop_setting_page.dart`（`sdTopTabs`、卡片/开关样式）、`main.dart`（窗口最小尺寸）、`mobile/pages/home_page.dart`（手机三标签）、`server_page.dart`（聊天按钮改为打开聊天页） | 新界面挂接 |
| `desktop_home_page.dart`（build / buildInstallCard / buildLeftPane 挂接）、`mobile/pages/connection_page.dart`、`server_page.dart`、`home_page.dart` | 新界面挂接：只替换外观，原有逻辑不变 |
| `flutter/windows/runner/Runner.rc`、`libs/portable/Cargo.toml` | 程序名称/描述（构建时按版本替换） |
| `flutter/android/app/build.gradle`、`AndroidManifest.xml` | 包名 `com.superdesk.remote`（可与官方 RustDesk 共存）、应用名 |
| 各平台图标 | `superdesk/branding/make_icons.py` 生成 |

`libs/hbb_common` 是 git 子模块，指向 [vulgar-sir/superdesk-hbb_common](https://github.com/vulgar-sir/superdesk-hbb_common)
的 `superdesk` 分支（官方 hbb_common + 上表两处改动），`git clone --recurse-submodules` 即可取到。改动另存为
`superdesk/patches/hbb_common.patch`，也可在官方提交上手动打补丁：
`git -C libs/hbb_common checkout fae47e024dd8 && git -C libs/hbb_common apply ../../superdesk/patches/hbb_common.patch`。

`APP_NAME`（`SuperDesk` / `SuperDeskHelper`）使客户端被识别为定制客户端：不检查官方更新；
配置目录、Windows 服务名、安装目录与官方 RustDesk 互不冲突。

### 升级到新版 RustDesk

1. `git fetch https://github.com/rustdesk/rustdesk.git tag <新版本>` 并合并，解决上表文件冲突。
2. 对照新版 `.github/workflows/flutter-build.yml`、`bridge.yml` 更新脚本/Dockerfile 中固定的 Rust/Flutter/vcpkg/NDK 版本。
3. 若客户端 API 有变化，跑 `superdesk/console/tests/smoke_test.py` 回归；重新生成桥接代码并构建两端。

## 已知事项

- 本机若开着 TUN 模式代理（Clash 等），端口探测会出现“假连通”，WebSocket 握手也可能被 HTTP 代理破坏；`check-p2p-ports.py` 已用服务器抓包规避。
- 访问策略中的“工作时间/公司账号”基于 RustDesk 的 ID 白名单实现，被拒绝的一方会看到“Your ID is blocked by the peer”。
- 设备 ID 由机器硬件标识计算：同一台电脑上同时运行完整版和员工助手会得到相同 ID、互相顶掉注册（正常部署一台电脑只装一个版本）。
- 许可证：本项目与 RustDesk 相同，为 AGPL-3.0（见根目录 `LICENCE`、`NOTICE.md`）。分发修改后的客户端时须同时提供源码，
  本仓库即为对应源码。
