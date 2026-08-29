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

> 状态：早期开发。各厂商接口可能随时变动。最终 v0.2 候选已烧录到 C152，并与
> 安装后的 Mac app 完成端到端验证，包括协议 v2 协商、完整 Active 计数和三家
> provider 同步。实体触摸/布局签收与长时功耗仍是后续验证项。

TokenLink 是独立的开源项目，与 OpenAI、Anthropic、Moonshot AI、MiniMax、
智谱 AI、M5Stack 均无隶属或背书关系，也不是它们的官方产品。各厂商名称与
商标归各自所有者。

## 最新动态

- **2026-08-30 — 最终候选首次通过 C152 端到端验证。** 固件提交
  [`0d5bf6c`](https://github.com/phantom5125/codex-micro-stopwatch/commit/0d5bf6c)
  经过哈希校验烧录后正常启动；TokenLink 0.2.0 协商 v2，并带完整 Active 数同步
  Codex、Kimi 和 MiniMax 的真实 payload。
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
- API key 只存 macOS 钥匙串（service `io.github.phantom5125.tokenlink.provider`）。
- 按 CoreBluetooth 标识绑定一台 StopWatch，写入使用 with-response 确认。
- 协商手表协议 v2，并在一次同步中发送全部所选额度源；v1 固件仍只接收完全不变的 Codex
  primary-window payload。
- 跟踪最多三个可命名 Codex 工作单元，并接收 v2 刷新/聚焦命令。聚焦会打开对应的
  `codex://threads/<id>` 任务链接，不兼容时回退为将 Codex Desktop 切到前台。
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
最终 bundle；每个 CI revision 也会生成开发用 artifact。v0.2.0 RC 下载目前仅支持
Apple Silicon 且使用 ad-hoc 签名，因此在 Developer ID 签名与 Apple 公证版发布前，
从源码构建仍是受支持的首次体验路径。

### 有 M5Stack StopWatch C152

1. 先完成上面的纯 Mac 步骤。
2. 从 [v0.2.0-rc.1 release](https://github.com/phantom5125/tokenLink/releases/tag/v0.2.0-rc.1)
   下载 `TokenLink-StopWatch-C152-0.2.0-rc.1.bin` 与对应 `.sha256`，也可以从真机验证过的
   [`0d5bf6c`](https://github.com/phantom5125/codex-micro-stopwatch/tree/0d5bf6c)
   源码构建；上游合并进度见
   [`digitsisyph/codex-micro-stopwatch#5`](https://github.com/digitsisyph/codex-micro-stopwatch/pull/5)。
   校验 checksum，解析并确认准确的 Espressif 串口，再把仅限 C152 的合并镜像烧录到
   `0x0`；源码仓库提供构建流程，M5Stack 提供
   [官方恢复流程](https://docs.m5stack.com/en/guide/restore_factory/stopwatch)。
3. 在 TokenLink 打开 **控制中心 → StopWatch**，扫描、选择准确设备、绑定，再点
   **立即同步手表**。

不要把 C152 镜像烧到其他 M5Stack 型号；协议 v1 固件也不会显示四页新 UI。RC 镜像
仍属于开发产物，上游固件 PR 与实体触摸/功耗签收尚未完成。

### 校验源码 checkout

```bash
swift build
bash scripts/test.sh
bash scripts/build_release_artifact.sh
```

最后一个命令会在 `dist/` 下生成带版本、架构和 SHA-256 的 `.zip`，并确认解压后的
可执行文件、Info.plist、资源 bundle 和签名都有效。维护者签名、公证和发布步骤见
[`docs/RELEASING.md`](docs/RELEASING.md)。

## 环境要求

- macOS 14 或更高版本
- Xcode 26+ / Swift 6.2+（仅用 Command Line Tools 也可构建 app；仓库自带的
  测试包装脚本会处理 CLT 缺少 Swift Testing 搜索路径的情况）
- Codex 额度需要本机可用的 `codex` CLI
- Claude 额度需要本机已登录的 Claude Code CLI
- 可选：运行匹配协议 v2 固件的 M5Stack StopWatch C152

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

TokenLink 读取 Claude Code 自带 `/usage` 所用的 OAuth 用量接口，只读复用 Claude
Code CLI 的钥匙串凭据项；过期的 token 会被忽略，refresh token 绝不读取。Anthropic
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

只有显式触发才会扫描。绑定后，所选额度源出现新鲜快照时会自动同步；连接、能力读取
和写入都有有限超时，额度写入使用 write-with-response。v1 固件只认识这个 payload：

```json
{"remaining_percent":72,"reset_in_seconds":900}
```

协议 v1 始终只发送 Codex primary 窗口；Kimi、Claude、MiniMax、GLM 绝不会在现有
v1 表盘上被误标为 Codex。

协议 v2 通过可选的只读 capabilities characteristic 协商。兼容设备可以接收最多三个
额度窗口、最多三个短名称工作单元、所选额度源轮转和表盘设置。只要发现、读取或解码
能力失败，TokenLink 就静默回退 v1。Mac 端实现和 fake transport 测试已经完成，最终
候选的完整 active count 与真实多 provider payload 也已送达 C152；实体布局/触摸检查
和长时功耗仍是独立的验证层。最新分层结果见 [`docs/validation`](docs/validation/)。

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
`io.github.phantom5125.tokenlink.provider`、account `kimi`/`minimax`/`glm` 删除。

## 架构

```text
TokenLinkApp        SwiftUI/AppKit 状态、设置、钥匙串、诊断
  ├─ TokenLinkCore       厂商中立的额度与刷新状态
  ├─ TokenLinkProviders  Codex/Claude/Kimi/MiniMax/GLM 适配器与 host 策略
  └─ TokenLinkDevice     v1/v2 投影、协商、命令与 CoreBluetooth 传输
```

每个 provider 都有 fixture 测试的解析器，产出统一的 `QuotaSnapshot`；新厂商通过
声明式 `ProviderSpec` 注册表接入。app 是唯一的 UI 状态所有者；设备层只接收经过
显式 v1/v2 投影的字段，不接触任何凭据。

## 协议 v2 状态

Mac 端已经实现 payload 投影、能力协商、v1 回退、provider 轮转、三个可见工作单元、
完整 active-task 数量、表盘设置、payload 预览和手表到 Mac 的命令通道。四页面表盘、
触摸聚焦、可选宠物主题和抬腕唤醒属于独立的 `codex-micro-stopwatch` 固件项目。最终
候选已通过 C152 烧录、启动、协议 v2 交换和多 provider 同步验证；实体布局/触摸检查
与 24 小时功耗浸泡尚未签收。

## 参与贡献

欢迎贡献代码和经过充分描述的想法。小型修复可直接提交；较大的 UI、协议、provider
或硬件改动应先提交 issue proposal。详见 [CONTRIBUTING.md](CONTRIBUTING.md)、
[行为准则](CODE_OF_CONDUCT.md)和仓库已有的 issue 模板。

## 许可证与致谢

TokenLink 采用 [Apache License 2.0](LICENSE)。必要署名与开发致谢见 [NOTICE](NOTICE)，
品牌使用边界见 [TRADEMARKS.md](TRADEMARKS.md)。
