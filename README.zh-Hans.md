# TokenLink

[English](README.md) | **简体中文**

[![CI](https://github.com/phantom5125/tokenLink/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/phantom5125/tokenLink/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

<!-- markdownlint-disable MD033 -->
<p align="center">
  <img
    src="assets/readme/tokenlink-watch-v2-hero.png"
    alt="M5Stack StopWatch 与 macOS 菜单栏额度面板"
    width="960">
</p>
<p align="center"><sub>首页 · 额度 · 会话 · 系统——Mac 与手腕上的同一份实时状态。</sub></p>
<!-- markdownlint-enable MD033 -->

TokenLink 是一个原生 macOS 菜单栏管控中枢，用于集中展示各家 AI 编程套餐的额度，
并可作为 M5Stack StopWatch 手表的伴随应用。0.2 版本在同一个本地界面里展示
Codex、Claude、Kimi、MiniMax 和 GLM 的额度，新增协商式手表协议 v2，同时保持
协议 v1 固件路径的字节级兼容。

> 状态：早期开发。各厂商接口可能随时变动。v0.2 界面已在 C152 上完成协议 v2
> 协商、完整 Active 计数、三家 provider 同步及实体 UI 反馈迭代。0.2.1 已将固件移入
> 本仓库并通过实体发布验收。0.2.2 候选新增连接诊断、明确的任务链接结果、完整 session
> 分页和更清晰的 C152 session 状态；新增硬件行为仍需完成下方清单。长时功耗仍是
> 后续验证项。

TokenLink 是独立的开源项目，与 OpenAI、Anthropic、Moonshot AI、MiniMax、
智谱 AI、M5Stack 均无隶属或背书关系，也不是它们的官方产品。各厂商名称与
商标归各自所有者。

## 最新动态

- **2026-08-30 — 0.2.2 稳定性候选已完成整合。** 蓝牙诊断、明确的 Codex 任务链接
  结果、完整 thread 分页、稳定优先级槽位和无障碍 C152 session 指示器已进入同一
  release 分支；组合测试为 190 项 Swift 测试和 12 个固件测试程序。
- **2026-08-30 — C152 固件已迁入 TokenLink。** 当前默认无线版源码、模拟器测试、
  分区表、MIT/OFL 声明及固定版本 PlatformIO 构建都位于
  `firmware/stopwatch-c152`；全新 checkout 不再需要另一个仓库即可构建 Mac 与固件制品。
- **2026-08-30 — 单仓镜像首次通过真实同步。** 新烧录的 C152 镜像与安装后的
  TokenLink 0.2.1 build 3 完成配对，并收到 Codex、Kimi、MiniMax 的真实 v2 更新。
- **2026-08-30 — 固件发布制品可被机器读取。** 现在会生成 C152 合并镜像、分片包、
  SHA-256 清单和产品/协议 manifest，后续本地固件 server 可直接消费。
- **2026-08-30 — 最终候选首次通过 C152 端到端验证。** 随 TokenLink RC 归档的固件
  revision `0d5bf6c` 经过哈希校验烧录后正常启动；TokenLink 0.2.0 协商 v2，并带完整
  Active 数同步 Codex、Kimi 和 MiniMax 的真实 payload。
- **2026-08-30 — 首页现在反映真实的 Codex 工作量。** 最新任务与状态压缩到同一行，
  Active 会统计所有 running 或 needs-input 的 Codex 任务，不再只数下发到表盘的三条。
- **2026-08-30 — Watch Face v2 进入发布候选状态。** 针对圆屏安全区设计 Home、Quota、
  Sessions、System 四页，手表与 Mac 使用一致的 provider 图标和额度条。
- **2026-08-29 — 手表与 Mac 成为同一个交互面。** 点击首页任务进入 Sessions，点击
  Codex session 会在 Mac 上打开对应的 `codex://threads/<id>` 任务。
- **2026-08-22 — 协议 v2 定型。** 在保持 v1 payload 兼容的前提下加入多 provider
  额度、具名任务、手表到 Mac 的刷新/聚焦指令和表盘设置。

## 功能

- 原生 `MenuBarExtra` 菜单栏 + 管控中心四个页面：概览、额度源、StopWatch、设置与诊断。
- 统一归一化多家、多窗口额度，绝不凭空推算套餐限额。
- 烧速预测：根据本地最近样本推算"按当前速度约几小时后耗尽"，不额外调用 API。
- 可选合理用量参考线，标出额度窗口在均匀消耗情况下应该所处的位置。
- 可选 Beta 本地用量观测：只读扫描 Codex、Claude、Kimi CLI 的已知会话目录，
  仅在本机汇总近期 token 计数。
- macOS 系统通知：窗口额度告急、窗口重置、凭据被拒时提醒（可在设置中关闭）。
- 刷新失败时保留最近一次成功快照并标记为 stale，绝不显示虚构的实时值。
- API key 只存 macOS 钥匙串（显示名称 `TokenLink`，service
  `app.tokenlink.provider`）。升级后不会自动读取 0.2.1 以前的旧 service；用户可在
  「额度源」页面先查看授权范围，再主动迁移。
- 按 CoreBluetooth 标识绑定一台 StopWatch，写入使用 with-response 确认。
- 提供不含凭据的连接检查表，分别显示蓝牙权限、适配器、绑定、连接进度、C04 通知、
  同步与脱敏失败类别。
- 协商手表协议 v2，并在一次同步中发送全部所选额度源；v1 固件仍只接收完全不变的 Codex
  primary-window payload。
- 分页读取完整 Codex thread 列表并报告完整 Active 数，同时保留三个稳定、按优先级
  排列的手表聚焦行。聚焦会向 Codex 投递对应 `codex://threads/<id>` 链接，并在不暴露
  任务标识的前提下显示准确的投递或回退结果。
- Session 生命周期每 10 秒独立刷新；只有明确完成才显示绿色 `DONE`。待处理任务在
  点击前为琥珀色动态 `ACTION`，点击后仍保持原执行状态，仅变为静态 `OPENED`；后续
  新状态会再次恢复待处理提示。
- 可配置 v2 主题、唤醒方式、时制与同步额度源，并在 StopWatch 页面预览最近 payload。
- 诊断导出前自动脱敏密钥、用户路径、账户标签和设备标识。
- 界面语言：English / 中文（简体）/ 日本語，跟随系统或手动选择。

## 快速开始

### 没有 M5Stack StopWatch

只体验 macOS 菜单栏时，这就是完整路径。需要 macOS 14+，以及 Xcode 26+ 或
Swift 6.2+ 工具链：

```bash
git clone https://github.com/phantom5125/tokenLink.git
cd tokenLink
bash scripts/package_app.sh
open TokenLink.app
```

打开 **控制中心 → 额度源**，启用 Codex 后刷新。TokenLink 会复用本机 Codex CLI
登录态，不保存 Codex API key；其他 provider 可以单独启用。

打包脚本会把 SwiftPM 图片资源装入 release-mode app，默认进行 ad-hoc 签名，并校验
最终 bundle；每个 CI revision 也会生成开发用 artifact。当前 Mac 下载仅支持
Apple Silicon 且使用 ad-hoc 签名，因此在 Developer ID 签名与 Apple 公证版发布前，
从源码构建仍是受支持的首次体验路径。

### 有 M5Stack StopWatch C152

1. 先完成上面的纯 Mac 步骤。
2. 安装固定版本工具，并直接从本 checkout 构建：

   ```bash
   python3.12 -m venv .venv-pio
   .venv-pio/bin/python -m pip install platformio==6.1.19
   bash scripts/test_firmware.sh
   bash scripts/build_firmware_artifact.sh
   ```

   最后一个命令会在 `dist/firmware/` 生成烧录到 `0x0` 的 C152-only 合并镜像、
   分片包、manifest 和校验清单。不想自行编译的用户可从
   [v0.2.2 release](https://github.com/phantom5125/tokenLink/releases/tag/v0.2.2)
   下载同类制品。
3. 阅读 M5Stack 的
   [官方恢复流程](https://docs.m5stack.com/en/guide/restore_factory/stopwatch)，识别本次
   新出现的准确 Espressif `/dev/cu.*` 串口，并在烧录前立即确认该端口：

   ```bash
   bash scripts/pio.sh run -d firmware/stopwatch-c152 \
     -e m5stack-stopwatch --target upload \
     --upload-port /dev/cu.YOUR_CONFIRMED_C152_PORT

   python3 firmware/stopwatch-c152/scripts/serial_probe.py \
     /dev/cu.YOUR_CONFIRMED_C152_PORT --seconds 30 \
     --expect CODEX_MICRO_STOPWATCH_READY
   ```

4. 在 TokenLink 打开 **控制中心 → StopWatch**，扫描、选择准确设备、绑定，再点
   **立即同步手表**。

不要把 C152 镜像烧到其他 M5Stack 型号；协议 v1 固件也不会显示四页新 UI。不要从
别人的命令或文档里照抄串口名。

### 校验源码 checkout

```bash
swift build
bash scripts/test.sh
bash scripts/test_firmware.sh
bash scripts/build_release_artifact.sh
bash scripts/build_firmware_artifact.sh
```

两个制品命令会在 `dist/` 下分别生成带校验的 Mac 与 C152 制品。维护者签名、公证、
硬件门槛和发布步骤见 [`docs/RELEASING.md`](docs/RELEASING.md)。

## 环境要求

- macOS 14 或更高版本
- Xcode 26+ / Swift 6.2+（仅用 Command Line Tools 也可构建 app；仓库自带的
  测试包装脚本会处理 CLT 缺少 Swift Testing 搜索路径的情况）
- Codex 额度需要本机可用的 `codex` CLI
- Claude 额度需要本机已登录的 Claude Code CLI
- 可选：M5Stack StopWatch C152；编译其固件需要 Python 3.12 和仓库固定的
  PlatformIO Core 6.1.19

## 配置各家额度源

打开 **控制中心 → 额度源**。密钥输入框永远空白：TokenLink 只显示凭据是否已配置、
已存密钥的头尾掩码（如 `sk-cp-ab…wxyz`）和凭据来源（钥匙串 / CLI / 环境变量），
绝不会把密钥回显到界面。每家区块都附官方控制台的获取链接。

凭据按以下顺序解析：钥匙串中的显式 key → 官方 CLI 的本机登录凭据（Kimi、Claude）
→ 少量环境变量 allowlist（`KIMI_CODE_API_KEY`/`KIMI_API_KEY`、`MINIMAX_API_KEY`、
`ZAI_API_KEY`/`ZHIPU_API_KEY`/`GLM_API_KEY`/`BIGMODEL_API_KEY`、
`CLAUDE_CODE_OAUTH_TOKEN`）。环境变量回退主要用于测试。

每家厂商支持多账户（进阶功能，不推荐）：在对应区块点 **添加账户（进阶）**，为另一
个套餐配置独立的名称和 key。Codex 和 Claude 因为走本机 CLI 登录态，保持单账户。

### Codex

TokenLink 启动本机 `codex app-server --listen stdio://`，完成 JSON-RPC 初始化握手后
读取 `account/rateLimits/read`。它复用 Codex CLI 自己的登录态，不保存任何 Codex
API key。如果 app 的 `PATH` 里找不到 `codex`，可以配置可执行文件的绝对路径。

### Claude

TokenLink 读取 Claude Code 自带 `/usage` 所用的 OAuth 用量接口，但启动时不会访问
Claude Code 的 `Claude Code-credentials` 钥匙串条目。用户必须先启用 Claude，再点击
明确的授权按钮；授权前说明会解释 macOS 开放的是整个该条目（不是整个钥匙串）、
TokenLink 只使用 access token 和有效期，以及何时适合选择“始终允许”。Anthropic
按量付费的 API key 查不到订阅额度，所以 Claude 刻意不提供 key 输入框。

### Kimi

可以在钥匙串中保存 Kimi Coding API key（在 [Kimi Code 控制台](https://www.kimi.com/code/console)
创建，`sk-kimi-` 前缀；注意开放平台的按量付费 key 不通用）。没有显式 key 时，
TokenLink 只读 `~/.kimi-code/credentials/kimi-code.json` 中当前未过期的 access token，
不读同目录其他文件、不读浏览器 Cookie、不读 refresh token，也绝不改写该文件。

### MiniMax

保存 MiniMax Coding Plan 的**订阅 Key**（`sk-cp-` 前缀，在平台的「订阅管理 →
Token Plan」页面获取，与按量付费 API Key 不互通），并选择 Global 或中国区域。
请求只发往所选官方 host（`www.minimax.io` 或 `www.minimaxi.com`）。

### GLM

保存 GLM Coding Plan API key，并选择 Global（Z.AI）或中国（BigModel）区域。
解析器保留服务端实际返回的各窗口，不根据套餐名称推算额度。

额度源启用状态和 Codex 路径的修改在重启 app 后生效；区域、账户、刷新间隔、语言、
通知开关的修改立即生效。

## StopWatch 绑定与协议 v1/v2

1. 保持匹配的 StopWatch 固件运行、蓝牙开启。
2. 打开 **控制中心 → StopWatch**，点 **扫描**。
3. 选择一个发现的设备标识并绑定。
4. 点 **立即同步手表**。

从旧的 `io.github.phantom5125.tokenlink` 身份升级时，TokenLink 0.2.1 会清除旧身份
保存的蓝牙设备标识，并在初始化蓝牙前说明一次性重绑要求。只有用户点“扫描”后才可能
出现 macOS 蓝牙弹窗；允许后，`app.tokenlink` 可以发现附近设备、连接 C152、同步额度
并接收手表命令，不会因此获得钥匙串访问权限。

只有显式触发才会扫描。绑定后，所选额度源出现新鲜快照时会自动同步；连接、能力读取
、命令通知订阅和写入都有有限超时。额度写入使用 write-with-response；对于协议 v2，
只有 macOS 确认 C04 手表命令通知订阅成功后，连接才会显示为 ready。v1 固件只认识
连接检查表会显示上述各项无凭据状态及恢复建议，不包含外设 UUID 或 payload。v1 固件
只认识这个 payload：

```json
{"remaining_percent":72,"reset_in_seconds":900}
```

协议 v1 始终只发送 Codex primary 窗口；Kimi、Claude、MiniMax、GLM 绝不会在现有
v1 表盘上被误标为 Codex。

协议 v2 通过可选的只读 capabilities characteristic 协商。兼容设备可以接收最多三个
额度窗口、最多三个短名称工作单元、所选额度源轮转和表盘设置。只要发现、读取或解码
能力失败，TokenLink 就静默回退 v1。0.2.1 已将完整 active count 与真实多 provider
payload 送达 C152。0.2.2 候选新增完整分页、稳定优先级槽位、聚焦投递反馈和不只依赖
颜色的状态动画；电源键短按唤醒修复已完成烧录和启动验证，实体布局、任务聚焦、重连
及可见睡眠/唤醒检查仍是最终候选验证层。最新
分层结果见 [`docs/validation`](docs/validation/)。

## 隐私与安全

- 显式 API key：只存 macOS 钥匙串。
- 非敏感配置：`~/Library/Application Support/TokenLink/config.json`，仅本人权限。
- 不读浏览器 Cookie，不需要完全磁盘访问权限，无埋点，无远端服务。
- 可选本地用量 Beta 只读取 `.codex/sessions`、`.claude/projects`、
  `.kimi-code/sessions`，仅在本机提取 token 计数，不上传会话内容。
- 所有厂商请求都是 HTTPS，且在携带凭据前校验官方 host allowlist。
- 诊断导出前脱敏。

漏洞报告与威胁边界见 [SECURITY.md](SECURITY.md)。

## 故障排查

- **Codex 不可用**：终端跑 `codex --version` 确认已登录；如菜单栏 app 的 `PATH`
  较小，在额度源页配置绝对路径。
- **Claude 需要凭据**：确认本机 Claude Code CLI 已登录且 token 未过期。
- **需要凭据**：在额度源页更换对应 key（旧值刻意不回显）。
- **额度显示 stale**：TokenLink 会保留最后成功快照并标注；网络恢复后手动刷新。
- **扫描不到 StopWatch**：确认固件暴露了私有额度 GATT 服务或 `Codex Micro` 设备名，
  并在 macOS 弹窗中允许蓝牙权限。
- **登录启动需要批准**：系统设置 → 通用 → 登录项中启用 TokenLink。

## 卸载

退出 TokenLink 并删除 `TokenLink.app`。可选删除配置：

```bash
rm -rf "$HOME/Library/Application Support/TokenLink"
```

钥匙串条目可在「钥匙串访问」中删除，或用 `security` 命令按 service
`app.tokenlink.provider`、account `kimi`/`minimax`/`glm` 删除。升级迁移会刻意保留
`io.github.phantom5125.tokenlink.provider` 下的恢复副本；确认新凭据正常后，可在
「钥匙串访问」中手动删除这些旧条目。

## 架构

```text
TokenLinkApp        SwiftUI/AppKit 状态、设置、钥匙串、诊断
  ├─ TokenLinkCore       厂商中立的额度与刷新状态
  ├─ TokenLinkProviders  Codex/Claude/Kimi/MiniMax/GLM 适配器与 host 策略
  └─ TokenLinkDevice     v1/v2 投影、协商、命令与 CoreBluetooth 传输

firmware/
  ├─ catalog.json              硬件/构建/协议注册表
  └─ stopwatch-c152/           PlatformIO C152 固件、UI 与原生测试
```

每个 provider 都有 fixture 测试的解析器，产出统一的 `QuotaSnapshot`；新厂商通过
声明式 `ProviderSpec` 注册表接入。app 是唯一的 UI 状态所有者；设备层只接收经过
显式 v1/v2 投影的字段，不接触任何凭据。

## 协议 v2 状态

Mac 端已经实现 payload 投影、能力协商、v1 回退、provider 轮转、三个可见工作单元、
完整 active-task 数量、表盘设置、payload 预览和手表到 Mac 的命令通道。配套四页面
C152 固件、触摸聚焦、可选宠物主题、抬腕唤醒和 host-native 测试现已位于
`firmware/stopwatch-c152`；该子树继续使用独立 MIT 许可证，并与 `TokenLinkDevice`
使用同一份 v1/v2 契约。上一候选已完成 C152 烧录、启动、协议 v2、多 provider 同步
及用户实体 UI 迭代；0.2.1 重建镜像已有独立的烧录、启动、真实同步、重连、C04
命令、实体 UI 与 session 聚焦验收记录。0.2.2 整合新增诊断、完整分页、聚焦反馈和
更清晰的 session 状态；实体清单与 24 小时功耗浸泡仍作为分离证据。

## 参与贡献

欢迎贡献代码和经过充分描述的想法。小型修复可直接提交；较大的 UI、协议、provider
或硬件改动应先提交 issue proposal。详见 [CONTRIBUTING.md](CONTRIBUTING.md)、
[行为准则](CODE_OF_CONDUCT.md)和仓库已有的 issue 模板。

## 许可证与致谢

TokenLink 的 Mac 与共享源码采用 [Apache License 2.0](LICENSE)；迁入的 C152 固件保留
自己的 [MIT 许可证](firmware/stopwatch-c152/LICENSE)，Space Mono 保留 OFL。必要署名
见 [NOTICE](NOTICE)，品牌使用边界见 [TRADEMARKS.md](TRADEMARKS.md)。
