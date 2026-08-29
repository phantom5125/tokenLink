# TokenLink macOS 管控中枢 v0.1 设计规范

**历史快照：** 本文记录 2026-08-19 的 v0.1 设计决策，其中许可证和
文件名以当时状态为准；当前许可证、通知与贡献规则以仓库根目录文件为准。

状态：已批准

日期：2026-08-19

目标平台：macOS 14 及以上、M5Stack StopWatch Dev Kit C152

## 1. 背景与决策

TokenLink 以 `codex-micro-stopwatch` 的已验证固件、BLE HID 兼容层和私有额度 GATT 服务为起点，增加一个可视化的 macOS 管控端，并把额度采集扩展到 Codex、Kimi、MiniMax 和 GLM Coding Plan。

v0.1 采用一个原生 macOS 应用：

- `MenuBarExtra` 提供常驻的快速状态入口；
- SwiftUI 设置窗口提供额度源、StopWatch 和诊断配置；
- CoreBluetooth、Keychain、额度刷新与 UI 运行在同一个应用进程；
- 不启动本地 Web Server，不引入后台 daemon，不要求浏览器 Cookie 或 Full Disk Access；
- Mac 显示全部四家额度，但旧版 StopWatch 只接收 Codex primary window，避免把其他供应商误标成 Codex。

该方案优先保证 macOS 集成、隐私边界和 BLE 稳定性。跨平台 Web UI 不属于 v0.1。

## 2. v0.1 范围

### 2.1 必须交付

1. 原生菜单栏应用和按需打开的设置窗口。
2. Codex、Kimi、MiniMax、GLM 四个独立额度适配器。
3. 统一额度模型，支持每个供应商一个或多个额度窗口。
4. API Key 通过 macOS Keychain 保存；允许只读复用明确列出的本地 CLI 登录凭据。
5. CoreBluetooth 发现、显式绑定、重连、写入确认和同步新鲜度状态。
6. 兼容 `codex-micro-stopwatch` 现有额度 GATT 服务和 JSON payload。
7. last-known-good 缓存、stale/error 展示、可脱敏诊断信息。
8. 纯 Swift 核心单元测试、Provider 响应解析测试、网络模拟测试和 BLE 状态机测试。
9. MIT 开源所需的 README、NOTICE、贡献与安全说明。

### 2.2 明确不进入 v0.1

- 不修改 StopWatch 固件、Codex Micro HID 行为或现有按钮映射。
- 不在旧表盘轮转 Kimi、MiniMax 或 GLM。
- 不发送供应商名称、账户身份、Prompt、任务文本、音频或任何凭据到手表。
- 不导入浏览器 Cookie，不请求 Full Disk Access，不做 UI 抓取。
- 不实现跨平台 Web UI、云同步、多 Mac 同步或远程控制。
- 不提供自动更新、用量历史数据库、成本估算或团队管理。

协议 v2 与表盘升级作为下一独立子项目：届时再加入 `provider_id`、多个额度窗口、表盘轮转、设备 Profile、Logo 和右键增强。

## 3. 技术选型

| 领域 | 选择 | 原因 |
| --- | --- | --- |
| 应用形态 | SwiftUI `MenuBarExtra` + Settings window | 原生后台生命周期、低打扰、无需本地端口 |
| 系统集成 | AppKit、CoreBluetooth、Security、ServiceManagement | 分别负责窗口细节、BLE、Keychain 和登录启动 |
| 并发 | Swift structured concurrency | Provider 可独立并发、超时和取消 |
| 包管理 | Swift Package Manager | 可通过命令行构建、模块和测试边界清晰 |
| 最低系统 | macOS 14 | 与参考项目和当前 BLE 行为保持一致 |
| Swift 工具链 | Swift 6.2 语言模式或更新版本 | 使用严格并发检查；本机现有 Swift 6.3 可构建 |
| 本地配置 | `Application Support/TokenLink/config.json` | 仅保存非敏感设置，原子写入 |
| Secret 存储 | macOS Keychain | 不把 API Key 写入 JSON、日志或 Git |

完整 Xcode 不是核心包和测试的构建前提；生成可分发 `.app`、签名和完整 UI 自动化时需要 Xcode。当前开发机只有 Command Line Tools，因此实现阶段先保证 `swift build`、`swift test` 和本地 `.app` 包装脚本可用，并把 Xcode 专属验证单独报告。

## 4. 模块边界

Swift Package 包含以下 targets：

### 4.1 `TokenLinkCore`

纯 Foundation 模块，定义：

- `ProviderID`、`ProviderDescriptor`；
- `QuotaSnapshot`、`QuotaWindow`、`QuotaFreshness`；
- `ProviderFetchOutcome` 和结构化错误；
- 刷新调度、last-known-good 合并和展示排序；
- 面向 UI 与设备投影的只读状态。

该模块不依赖 SwiftUI、CoreBluetooth、Security 或具体 Provider。

### 4.2 `TokenLinkProviders`

实现 `QuotaProvider` 协议，每个 Provider 放在独立目录。Provider 只能通过宿主提供的窄接口访问：

- `HTTPClient`：限定 HTTPS 和 Provider 官方 host allowlist；
- `CredentialReader`：读取当前 Provider 的 Keychain 项或允许的 CLI 凭据；
- `ProcessRunner`：仅 Codex Adapter 可用于启动本机 Codex App Server；
- `ProviderLogger`：默认脱敏，不接受原始 token、Cookie 或响应头。

Provider 不直接调用 `FileManager`、Security framework 或任意 URL。

### 4.3 `TokenLinkDevice`

封装 CoreBluetooth：

- 按私有额度 Service UUID 发现设备；
- 首次绑定展示 CoreBluetooth UUID，由用户明确选择；
- 后续只连接已绑定 UUID；
- 发现 write characteristic、使用 with-response 写入并处理 ACK；
- 跟踪 disconnected、connecting、connected、syncing、synced 和 stale；
- 将 `QuotaSnapshot` 转换为版本化设备 payload。

该模块不接触 Provider 凭据。

### 4.4 `TokenLinkApp`

SwiftUI 可执行应用，负责：

- `MenuBarExtra` 和管控中心窗口；
- `AppModel` 对核心状态的 `MainActor` 投影；
- Keychain 的具体实现；
- 非敏感设置持久化；
- 登录启动、手动刷新和诊断导出。

依赖方向固定为：

```text
TokenLinkApp -> TokenLinkProviders -> TokenLinkCore
TokenLinkApp -> TokenLinkDevice    -> TokenLinkCore
```

`TokenLinkProviders` 与 `TokenLinkDevice` 互不依赖。

## 5. 统一额度模型

每次成功采集产生一个 `QuotaSnapshot`：

```text
QuotaSnapshot
  provider: ProviderID
  planLabel: String?
  windows: [QuotaWindow]
  source: apiKey | cliCredential | localAppServer
  fetchedAt: Date

QuotaWindow
  id: stable provider-local identifier
  label: 5 hours | weekly | monthly | primary
  usedPercent: Double?
  remainingPercent: Double
  remainingCount: Double?
  limitCount: Double?
  resetsAt: Date?
```

规则：

- 百分比进入核心前统一 clamp 到 `0...100`；
- Provider 只返回使用量时，由 Adapter 计算剩余量；
- 缺失的绝对计数保持 `nil`，不得猜测；
- reset 时间统一为绝对 `Date`，UI 再生成本地倒计时；
- 多个窗口不得被压缩成一个平均值；
- UI 默认按“剩余最少的健康窗口”突出风险，但始终显示 Provider 名称和窗口标签。

## 6. Provider 设计

### 6.1 Codex

- 发现本机 `codex` 可执行文件，或使用用户配置的绝对路径。
- 启动 `codex app-server --listen stdio://`。
- 初始化后调用 `account/rateLimits/read`。
- 优先解析 `rateLimitsByLimitId.codex`，兼容旧 `rateLimits.limitId == codex` 结构。
- 使用本机现有登录上下文，不读取或保存 OpenAI token。
- App Server 生命周期由 Adapter 管理；退出和超时必须终止子进程。

### 6.2 Kimi

凭据优先级：

1. TokenLink Keychain 中显式配置的 Kimi Coding API Key；
2. 官方 Kimi Code CLI 当前有效的 access token，只读读取已知凭据文件。

请求 `https://api.kimi.com/coding/v1/usages`，解析 weekly 和 rolling 5-hour windows。TokenLink 不使用 refresh token、不改写 CLI 文件；CLI access token 过期时提示用户重新登录或配置 API Key。

### 6.3 MiniMax

- 使用 TokenLink Keychain 中的 Coding Plan API Key。
- 根据用户选择的 Global/CN region 使用官方 MiniMax host。
- 初始实现使用官方 Token Plan remains 接口，并兼容仍在使用的 Coding Plan remains 响应结构。
- Parser 对字段命名差异使用显式、带测试的兼容分支，不接受任意动态 host。

### 6.4 GLM

- 使用 TokenLink Keychain 中的 GLM Coding Plan API Key。
- 支持 Global `api.z.ai` 与中国区 `open.bigmodel.cn` 的显式 region 选择。
- 调用官方 `/api/monitor/usage/quota/limit` 用量接口。
- 保留 5-hour、weekly、monthly 等服务实际返回的独立窗口，不根据套餐名称推算额度。

### 6.5 与 CodexBar 的关系

TokenLink 参考 CodexBar 的 descriptor、fetch strategy 和 normalized snapshot 边界，并在 NOTICE 中注明 MIT 来源。v0.1 不 fork CodexBar，也不把 `CodexBarCore` 作为运行依赖，原因是该模块还携带 Cookie、QuickJS、SQLite 和大量当前无关 Provider 能力。

若实现阶段改编了具体源文件，NOTICE 必须列出文件、上游提交和许可证；仅参考接口行为和公开响应结构时也保留项目级致谢。

## 7. 凭据与隐私

- Keychain service 固定为 `io.github.phantom5125.tokenlink.provider`，account 使用稳定 Provider ID。
- 非敏感配置只记录 Provider 是否启用、region、刷新间隔、Codex 可执行路径和绑定设备 UUID。
- CLI 凭据读取使用逐 Provider allowlist；不存在通用 home-directory 扫描。
- 不读取浏览器 Cookie、localStorage、历史记录或保存的密码。
- 不把 API Key、access token、refresh token、账户标识、设备 UUID 或本机路径写入 Git。
- 日志只包含 Provider ID、阶段、耗时、HTTP 状态类别和脱敏错误；不得记录 Authorization header 或原始响应正文。
- 手表 payload 永远不包含凭据、账户身份或请求内容。
- 自定义 endpoint 不进入 v0.1，所有远程请求必须是 HTTPS 且 host 在代码 allowlist 中。

## 8. 刷新、缓存与状态

### 8.1 刷新策略

- 应用启动后立即刷新已启用 Provider。
- 默认后台间隔为 5 分钟，可选 1、2、5、15 或 30 分钟。
- 单个 Provider 超时为 20 秒；Codex App Server 首次启动允许 30 秒。
- Provider 并发刷新，某一家失败不阻塞其他结果。
- 手动刷新最短间隔为 10 秒，避免误触造成请求风暴。
- 睡眠唤醒、网络恢复或 BLE 重连后进行一次带抖动的刷新。

### 8.2 状态模型

每个 Provider 独立处于：

- `disabled`；
- `missingCredential`；
- `refreshing`；
- `healthy`；
- `stale`：存在 last-known-good，但超过两个正常刷新周期；
- `error`：从未成功，或缓存已超过 24 小时。

失败时保留 last-known-good 和原始采集时间。UI 不把缓存数据显示为实时值。

## 9. StopWatch v1 兼容

v0.1 沿用参考项目的私有额度 GATT Service 和 write characteristic UUID，payload 保持：

```json
{
  "remaining_percent": 72,
  "reset_in_seconds": 356400
}
```

投影规则：

1. 仅选择 Codex primary window。
2. `reset_in_seconds` 在发送时由 `resetsAt - now` 计算并 clamp 到非负整数。
3. 没有健康或可接受的 stale Codex 快照时不发送虚构的 0%；设备保持旧值并按现有 TTL 标记 stale。
4. 只向用户已绑定的 CoreBluetooth UUID 写入。
5. ATT ACK 仅证明写入完成；Mac UI 单独展示 BLE 连接和额度新鲜度。

固件、HID、Agent 六槽状态、左键 PTT、右键 Voice Chat、中央 Send 与滑动手势在 v0.1 中保持不变。

## 10. Mac 信息架构

### 10.1 菜单栏 Popover

- 顶部：StopWatch 连接与最近同步状态。
- 中部：四个 Provider 的最紧张窗口、剩余百分比、窗口标签和 reset 倒计时。
- 底部：立即刷新、打开管控中心。
- 菜单栏 meter 显示当前“剩余最少的健康窗口”，并使用 Provider 标识避免误读。

### 10.2 管控中心

1. **总览**：Provider 卡片、StopWatch 卡片、最近本地事件。
2. **额度源**：启用状态、凭据来源、region、测试连接、最近成功与结构化错误。
3. **StopWatch**：发现、绑定/解绑、连接状态、协议版本、立即同步。
4. **设置与诊断**：刷新间隔、登录启动、脱敏日志和诊断导出。

侧栏可显示不可点击的“表盘与 Logo · 协议 v2”路线图提示，但 v0.1 不创建空设置页或不可用控件；README 同步说明该能力属于下一子项目。

## 11. 错误处理与可诊断性

- 网络、身份验证、响应解析、进程、BLE 和配置错误使用不同 error kind。
- 用户界面提供简短原因和明确动作，例如“重新登录 Kimi CLI”“更新 Keychain API Key”“重新连接已绑定设备”。
- Parser 不静默吞掉未知响应；保留脱敏后的响应 shape 摘要供诊断。
- 配置文件使用临时文件加原子替换，损坏时保留原文件并回退安全默认值。
- Keychain 拒绝访问时不降级到明文存储。
- BLE 写入失败使用有限指数退避；用户手动断开或解绑后不自动重连。
- 诊断导出默认移除用户名、home 路径、设备 UUID、账户标签和所有 token-like 字段。

## 12. 测试与验证

### 12.1 自动化测试

- `TokenLinkCoreTests`：百分比归一化、多窗口排序、缓存和状态跃迁。
- `TokenLinkProviderTests`：四家成功、缺字段、错误 envelope、时间格式和兼容响应 fixture。
- `HTTPClientTests`：host allowlist、HTTPS、超时、状态码和 header 脱敏。
- `CredentialVaultTests`：使用 fake vault 验证优先级；不在测试中访问真实 Keychain。
- `CodexAppServerTests`：使用 fake JSONL 子进程验证初始化、请求关联、超时和退出。
- `TokenLinkDeviceTests`：payload 编码、大小限制、绑定过滤、连接状态和重试。
- `AppModelTests`：Provider 独立失败、手动刷新节流、菜单栏突出规则。

所有网络测试使用 `URLProtocol` 或注入式 `HTTPClient`，不访问真实供应商账户。

### 12.2 本机验证层级

验证结果必须分层报告：

1. Swift 包编译与单元测试；
2. macOS 应用启动、菜单栏和设置窗口；
3. Keychain 写入/读取和拒绝路径；
4. 使用用户已有账户的真实 Provider 刷新；
5. BLE 发现与绑定；
6. 现有固件的真实 Codex 额度更新。

构建成功不能替代真机验证。没有连接 C152 或没有真实账户时，相应层级必须标记为未验证。

## 13. 开源与仓库标准

- 项目继续使用现有 MIT License。
- 保留 `codex-micro-stopwatch` 的 MIT attribution，并新增 `NOTICE.md` 说明衍生关系。
- README 明确项目不是 OpenAI、Moonshot AI、MiniMax、Zhipu AI 或 M5Stack 官方产品。
- 不提交设备 UUID、用户名、绝对 home 路径、日志、真实响应 fixture 或凭据。
- fixture 必须人工清洗并用合成值替换身份信息。
- CI 至少运行 `swift build`、`swift test` 和格式检查。
- Provider 新增流程要求：descriptor、adapter、fixture、parser test、安全 host allowlist 和用户文档同时提交。

## 14. 后续子项目：协议 v2 与表盘升级

完成并验证 v0.1 后，下一份独立设计规范覆盖：

- 版本协商与向后兼容 payload；
- 多 Provider、多窗口轮转；
- Mac 配置的设备 Profile 与开源 Logo 资产；
- 用更少、更可记忆的工作单元替代固定六个匿名会话圆；
- 左键继续 PTT；右键改为短按切换页面、长按执行可配置快捷动作；
- 表盘离线、stale、需要输入和完成提醒的视觉层级；
- 固件模拟器、BLE 协议测试和 C152 真机验证清单。

该后续设计不得破坏 v1 payload 或把账户凭据下放到固件。

## 15. v0.1 完成判定

只有同时满足以下条件，v0.1 才能标记完成：

1. 四个 Provider 均有可重复的解析测试和至少一个真实账户验证结果；无法验证的 Provider 必须明确列为未完成。
2. 菜单栏和管控中心展示一致的快照、新鲜度和错误状态。
3. API Key 仅存在于 Keychain，日志与配置扫描不含秘密。
4. 已绑定 StopWatch 能收到与 Mac 一致的 Codex primary window 和 reset 倒计时。
5. 网络失败、凭据失效和 BLE 中断不会导致崩溃或显示虚构实时值。
6. `swift build`、`swift test`、格式检查和隐私扫描通过。
7. README、NOTICE、安全说明、安装和卸载步骤完整。
