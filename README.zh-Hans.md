# TokenLink

[English](README.md) | **简体中文**

TokenLink 是一个原生 macOS 菜单栏管控中枢，用于集中展示各家 AI 编程套餐的额度，
并可作为 M5Stack StopWatch 手表的伴随应用。当前版本在同一个本地界面里展示
Codex、Claude、Kimi、MiniMax 和 GLM 的额度，同时保持对现有
`codex-micro-stopwatch` 固件的兼容。

> 状态：早期开发。各厂商接口可能随时变动。Mac 应用已实现并有完整测试；
> 真机验证与自动化兼容性测试分开跟踪。

TokenLink 是独立的开源项目，与 OpenAI、Anthropic、Moonshot AI、MiniMax、
智谱 AI、M5Stack 均无隶属或背书关系，也不是它们的官方产品。各厂商名称与
商标归各自所有者。

## 功能

- 原生 `MenuBarExtra` 菜单栏 + 管控中心四个页面：概览、额度源、StopWatch、设置与诊断。
- 统一归一化多家、多窗口额度，绝不凭空推算套餐限额。
- 烧速预测：根据本地最近样本推算"按当前速度约几小时后耗尽"，不额外调用 API。
- macOS 系统通知：窗口额度告急、窗口重置、凭据被拒时提醒（可在设置中关闭）。
- 刷新失败时保留最近一次成功快照并标记为 stale，绝不显示虚构的实时值。
- API key 只存 macOS 钥匙串（service `io.github.phantom5125.tokenlink.provider`）。
- 按 CoreBluetooth 标识绑定一台 StopWatch，写入使用 with-response 确认。
- 绑定后每次 Codex 快照刷新自动同步手表，带有限超时/重试和断连状态跟踪。
- 诊断导出前自动脱敏密钥、用户路径、账户标签和设备标识。
- 界面语言：English / 中文（简体）/ 日本語，跟随系统或手动选择。

## 环境要求

- macOS 14 或更高版本
- Xcode 26+ / Swift 6.2+（仅用 Command Line Tools 也可构建 app；仓库自带的
  测试包装脚本会处理 CLT 缺少 Swift Testing 搜索路径的情况）
- Codex 额度需要本机可用的 `codex` CLI
- Claude 额度需要本机已登录的 Claude Code CLI
- 可选：运行现有 `codex-micro-stopwatch` 固件的 M5Stack StopWatch

## 构建与运行

```bash
git clone https://github.com/phantom5125/tokenLink.git
cd tokenLink
swift build
bash scripts/test.sh
bash scripts/package_app.sh
open TokenLink.app
```

打包脚本会构建 release、生成 `TokenLink.app`、进行 ad-hoc 签名并校验。
日常使用建议把 app 移到 `/Applications`。公证发布流程暂不在当前版本范围内。

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

## StopWatch 绑定与协议 v1

1. 保持 StopWatch 固件运行、蓝牙开启。
2. 打开 **控制中心 → StopWatch**，点 **扫描**。
3. 选择一个发现的设备标识并绑定。
4. 点 **立即同步 Codex**。

只有显式触发才会扫描。绑定后 Codex 刷新成功会自动同步；连接与写入都有有限超时，
并使用 write-with-response。v1 固件只认识这个 payload：

```json
{"remaining_percent":72,"reset_in_seconds":900}
```

为了准确，当前版本只向手表发送 Codex 的 primary 窗口；Kimi、Claude、MiniMax、GLM
只在 Mac 上展示，绝不会在现有表盘上被误标为 Codex。

## 隐私与安全

- 显式 API key：只存 macOS 钥匙串。
- 非敏感配置：`~/Library/Application Support/TokenLink/config.json`，仅本人权限。
- 不读浏览器 Cookie，不需要完全磁盘访问权限，无埋点，无远端服务。
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
  └─ TokenLinkDevice     v1 投影、绑定与 CoreBluetooth 传输
```

每个 provider 都有 fixture 测试的解析器，产出统一的 `QuotaSnapshot`；新厂商通过
声明式 `ProviderSpec` 注册表接入。app 是唯一的 UI 状态所有者；设备层只接收经过
显式投影的字段，不接触任何凭据。

## 协议 v2 路线图

下一个固件阶段是增量且带版本的：多 provider 轮转、Mac 端配置的表盘资料、更少
更可记忆的会话槽位、以及更顺手的右键动作。协议 v1 兼容保持独立路径，已有手表
在迁移期间继续可用。设计草案见 `docs/specs/`。

## 许可证

MIT。见 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md)。
