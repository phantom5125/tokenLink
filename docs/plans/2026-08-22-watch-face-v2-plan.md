# TokenLink 表盘与协议 v2 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the approved-direction watch face and protocol v2 design (`docs/specs/2026-08-22-watch-face-v2-design.md`): a versioned multi-provider quota payload, named work items with Codex tap-to-focus, a watch→Mac command channel, watch configuration in the Mac control center, and coordinated firmware work in `codex-micro-stopwatch`.

**Architecture:** All Mac-side v2 protocol logic lands in `TokenLinkDevice` (payload, negotiation, command channel) and `TokenLinkCore` (work item models); Codex session tracking extends `TokenLinkProviders/Codex`; watch settings and the new 表盘 UI live in `TokenLinkApp`. Firmware work happens in the separate `codex-micro-stopwatch` repository and is tracked here as external tasks with acceptance criteria.

**Tech Stack:** Swift 6.2, SwiftUI, CoreBluetooth, Foundation; firmware: ESP32-S3 / PlatformIO (external repo).

**执行状态（2026-08-30）：** TokenLink Mac 端 Task 1–6 已实现；Task 7 的外部
`codex-micro-stopwatch` 源码、原生预览和模拟器测试已完成，最终候选也已在确认的
C152 上完成烧录、启动、v2 协商与三 provider payload 同步。focus 现在打开匹配的
`codex://threads/<id>` 任务，并保留仅激活 Codex Desktop 的兼容回退。实体布局/触摸、
24 小时功耗与正式签名发布产物仍按独立验证层跟踪。最新证据见
`docs/validation/2026-08-30-v0.2-release-readiness.md`。

**前置约定:**

- 设计文档是本计划的准绳；若实现中发现设计冲突，先改设计文档并说明原因。
- 测试只能跑 `bash scripts/test.sh`（本机 CLT 不带 Testing 框架路径）。
- v1 兼容性红线：`LegacyWatchProjection` 与固件 v1 行为一个字节都不能变；v2 全部走协商，协商失败必须静默回退 v1。
- 隐私红线：payload/命令通道不含凭据、账户标识、prompt、任务文本；work item name 限 12 ASCII 字符，Mac 端截断校验。
- 当前基线：170 个测试全绿。

---

## Task 1: 协议 v2 数据模型与编解码

**Files:**
- Create: `Sources/TokenLinkDevice/WatchPayloadV2.swift`
- Create: `Tests/TokenLinkDeviceTests/WatchPayloadV2Tests.swift`

- [ ] **Step 1: 写失败的编解码测试**

覆盖：完整 v2 payload round-trip；`windows` 超过 3 个时编码端截断报错；`name` 超过 12 字符或非 ASCII 时 Mac 端截断/拒绝；未知字段被解码端忽略（前向兼容）；`state`/`source` 非枚举值映射为 `.unknown` 而不是崩溃。

- [ ] **Step 2: 实现模型**

```swift
public enum WorkItemState: String, Codable, Sendable {
  case running, needsInput = "needs_input", completed, failed, unknown
}

public struct WorkItemPayload: Codable, Equatable, Sendable {
  public let slot: Int        // 0...2
  public let name: String     // ≤ 12 ASCII，Mac 端截断
  public let source: String   // ProviderID.rawValue
  public let state: WorkItemState
}

public struct WatchWindowPayload: Codable, Equatable, Sendable {
  public let id: String              // "5h" | "weekly" | "monthly" | "primary"
  public let remainingPercent: Double
  public let resetInSeconds: Int
  enum CodingKeys: String, CodingKey {
    case id
    case remainingPercent = "remaining_percent"
    case resetInSeconds = "reset_in_seconds"
  }
}

public struct WatchPayloadV2: Codable, Equatable, Sendable {
  public let v: Int                 // 固定 2
  public let providerID: String
  public let windows: [WatchWindowPayload]     // ≤ 3
  public let workItems: [WorkItemPayload]      // ≤ 3
  public let syncedAt: Int
  enum CodingKeys: String, CodingKey {
    case v, windows
    case providerID = "provider_id"
    case workItems = "work_items"
    case syncedAt = "synced_at"
  }
}
```

- [ ] **Step 3: 实现 v2 投影**

`WatchProjectionV2.encode(snapshot:workItems:now:)`：从 `QuotaSnapshot` 取最多 3 个窗口（优先级 5h > weekly > monthly > 其他），`reset_in_seconds` 发送时计算并 clamp 非负；总字节数上限沿用 512 检查。不拒绝非 Codex provider（v2 与 v1 的关键差异），但没有健康/可接受 stale 快照时仍不发送虚构值。

- [ ] **Step 4: 验证并提交**

Run: `bash scripts/test.sh --filter TokenLinkDeviceTests`（若 wrapper 不支持 filter 则全量）

Expected: PASS。

```bash
git add Sources/TokenLinkDevice Tests/TokenLinkDeviceTests
git commit -m "feat: add watch protocol v2 payload models"
```

## Task 2: 版本协商与 v1 回退

**Files:**
- Create: `Sources/TokenLinkDevice/WatchCapabilities.swift`
- Modify: `Sources/TokenLinkDevice/DeviceModels.swift`
- Modify: `Sources/TokenLinkDevice/CoreBluetoothDeviceBridge.swift`
- Create: `Tests/TokenLinkDeviceTests/WatchNegotiationTests.swift`

- [ ] **Step 1: 写失败的协商测试**

用 fake BLETransport 覆盖：固件报告支持 v2 → 后续 sync 发 v2 payload；固件只认 v1（或协商读取超时/特征不存在）→ 静默回退 `LegacyWatchProjection`；协商结果在连接存续期内缓存，重连后重新协商。

- [ ] **Step 2: 定义协商模型**

```swift
public struct WatchCapabilities: Codable, Equatable, Sendable {
  public let protocolVersions: [Int]   // 固件支持的版本列表，如 [1, 2]
  public let firmware: String?         // 展示用，可为 nil
}

public enum NegotiatedProtocol: Equatable, Sendable {
  case v1
  case v2(WatchCapabilities)
}
```

- [ ] **Step 3: 接入 DeviceBridge**

新增只读 GATT characteristic（建议 UUID `7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C03`，固件侧同步新增）。`connect()` 成功后、`sync()` 首次调用前读取 capabilities；任何读取失败都回退 v1 并记录事件。`BLETransport` 协议加 `readCapabilities() async throws -> WatchCapabilities?`，CoreBluetooth 实现保持"每个回调恰好 resume 一次"的现有约束。

- [ ] **Step 4: 验证并提交**

Run: `bash scripts/test.sh`

Expected: PASS，且 `LegacyWatchProjection` 既有测试原样通过（v1 未被触碰）。

```bash
git add Sources/TokenLinkDevice Tests/TokenLinkDeviceTests
git commit -m "feat: negotiate watch protocol with v1 fallback"
```

## Task 3: 手表 → Mac 命令通道与 Codex 聚焦

**Files:**
- Create: `Sources/TokenLinkDevice/WatchCommand.swift`
- Modify: `Sources/TokenLinkDevice/CoreBluetoothDeviceBridge.swift`
- Create: `Sources/TokenLinkApp/FocusHandler.swift`
- Create: `Tests/TokenLinkDeviceTests/WatchCommandTests.swift`
- Create: `Tests/TokenLinkAppTests/FocusHandlerTests.swift`

- [ ] **Step 1: 写失败的命令解码测试**

```swift
public enum WatchCommand: Equatable, Sendable {
  case focus(slot: Int)
}
```

解码规则：合法 JSON + 已知 action → 对应命令；slot 越界、未知 action、畸形 JSON → 丢弃并计数（诊断用），不抛给 UI。

- [ ] **Step 2: 实现命令通道**

新增可写 characteristic（建议 UUID `7F0D4E66-2AC2-4A71-BFBE-4EF61A0E5C04`）接收手表写入。`DeviceBridge` 暴露 `commandStream: AsyncStream<WatchCommand>`；仅在协商为 v2 时启用。

- [ ] **Step 3: 实现 Mac 侧聚焦**

`FocusHandler`（协议 + 实现分离，测试注入 fake）：收到 `.focus(slot)` → 查 `WorkItemStore` 里该 slot 的会话记录 → 仅当 source == codex 时执行：激活 Codex Desktop（NSWorkspace），并经 app-server 选中对应 thread。找不到会话或非 Codex → 记录事件、不报错。**聚焦目标的具体 app-server 方法在实现时对照本机 codex 版本验证**（设计文档第 3/9 节已注明）。

- [ ] **Step 4: 验证并提交**

Run: `bash scripts/test.sh`

```bash
git add Sources/TokenLinkDevice Sources/TokenLinkApp Tests
git commit -m "feat: add watch command channel and Codex focus"
```

## Task 4: Codex 工作单元跟踪

**Files:**
- Create: `Sources/TokenLinkCore/WorkItemModels.swift`
- Create: `Sources/TokenLinkProviders/Codex/CodexWorkItemTracker.swift`
- Create: `Tests/TokenLinkProviderTests/CodexWorkItemTests.swift`

- [ ] **Step 1: 写失败的状态转换测试**

thread 回合开始 → `.running`；等待用户输入 → `.needsInput`；回合完成 → `.completed`；错误 → `.failed`；同一 slot 复用、超过 3 个会话时按最近活跃取舍。

- [ ] **Step 2: 实现 WorkItemStore（core 层）**

```swift
public struct WorkItem: Equatable, Sendable, Identifiable {
  public let id: String          // Mac 内部会话标识，不下传
  public var slot: Int           // 0...2，下传给手表
  public var name: String        // Mac 端命名，≤ 12 ASCII
  public var source: ProviderID
  public var state: WorkItemState
  public var updatedAt: Date
}

public actor WorkItemStore { /* slot 分配、最近活跃淘汰、快照导出 */ }
```

- [ ] **Step 3: 实现 Codex 跟踪器**

基于 `CodexAppServerClient` 的现有 JSONL transport 订阅会话/回合事件（具体 notification 方法名以本机 codex app-server 实际协议为准，先探测再映射），产出 `WorkItem` 更新。全部通过 fake transport 测试，不依赖真实 codex 进程。

- [ ] **Step 4: 验证并提交**

Run: `bash scripts/test.sh`

```bash
git add Sources/TokenLinkCore Sources/TokenLinkProviders/Codex Tests
git commit -m "feat: track Codex sessions as watch work items"
```

## Task 5: 手表配置模型与同步策略

**Files:**
- Modify: `Sources/TokenLinkApp/ConfigurationStore.swift`
- Create: `Sources/TokenLinkApp/WatchSyncPolicy.swift`
- Modify: `Sources/TokenLinkApp/AppModel.swift`
- Create: `Tests/TokenLinkAppTests/WatchSyncPolicyTests.swift`

- [ ] **Step 1: 写失败的配置与策略测试**

`AppConfiguration` 新增（自定义解码保持旧配置兼容）：

```swift
public struct WatchSettings: Codable, Equatable, Sendable {
  public var syncedProviders: Set<ProviderID>  // 默认 [.codex]
  public var faceTheme: FaceTheme              // .data（默认）/ .pet
  public var wakeMode: WakeMode                // .raiseToWake（默认）/ .tapOnly
  public var hourFormat: HourFormat            // .system（默认）/ .h12 / .h24
}
```

策略测试覆盖：默认配置下只有 Codex 快照参与同步（v1 行为等价）；多 provider 时按"各 provider 最新快照 + 页面无关的轮转"生成发送序列；某家 stale 超过阈值时从轮转中剔除；手表未协商 v2 时即使配置了多家也只发 Codex v1。

- [ ] **Step 2: 实现 WatchSyncPolicy**

输入：协商结果 + 各 provider 最新 `ProviderState` + `WatchSettings`；输出：下一条要发送的 payload（v1 或 v2）。纯函数，全部单测。

- [ ] **Step 3: 接入 AppModel 刷新链路**

刷新成功 → 经 `WatchSyncPolicy` 决定 → 写手表。替换现有"只看 Codex"的直写路径，保持既有自动同步测试语义（默认配置下行为不变）。

- [ ] **Step 4: 验证并提交**

Run: `bash scripts/test.sh`

```bash
git add Sources/TokenLinkApp Tests/TokenLinkAppTests
git commit -m "feat: add watch sync policy and settings model"
```

## Task 6: 管控中心"表盘"配置 UI 与 payload 预览

**Files:**
- Modify: `Sources/TokenLinkApp/Views/StopWatchView.swift`
- Create: `Sources/TokenLinkApp/Views/WatchFaceSettingsView.swift`
- Modify: `Sources/TokenLinkApp/Strings.swift`
- Modify: `Tests/TokenLinkAppTests/LocalizationTests.swift`（如结构需要）

- [ ] **Step 1: StopWatch 页新增"表盘"区块**

按设计第 9 节：同步 provider 多选（默认仅 Codex）、工作单元命名列表（三个 slot，可改名）、表盘主题（数据/宠物，默认数据）、唤醒方式（抬腕/仅点按）、12/24 小时制。全部写入 `WatchSettings` 并即时下发（payload 内的设置段，见 Task 2 协商）。

- [ ] **Step 2: v2 payload 预览**

StopWatch 页显示最近一次实际发送的 payload JSON（脱敏后）+ 协商到的协议版本 + 固件版本字符串（如有）。

- [ ] **Step 3: i18n**

所有新文案进 `L10n` catalog，三种语言（en / zh-Hans / ja）补齐；`catalogCoversEveryKeyInEveryLanguage` 自动守住完整性。

- [ ] **Step 4: 验证并提交**

Run: `bash scripts/test.sh`；`bash scripts/package_app.sh`；`open TokenLink.app` 人工走查新区块。

```bash
git add Sources/TokenLinkApp Tests/TokenLinkAppTests
git commit -m "feat: add watch face settings and payload preview"
```

## Task 7: 固件协调任务（外部仓库 codex-micro-stopwatch）

以下工作在固件仓库实施，本计划只定义接口契约与验收标准；TokenLink 侧用特征开关兼容旧固件。

- [ ] **Step 1: 固件新增 capabilities characteristic（`…C03`）**，返回 `{"protocol_versions":[1,2],"firmware":"<version>"}`。验收：旧 Mac companion（v0.1）连接该固件行为不变。
- [ ] **Step 2: 固件四页面结构**（P0 主页 / P1 额度 / P2 会话 / P3 系统）+ 按键映射按设计第 4 节：右键短按翻页、右键长按回主页、中央键长按承接 Voice Chat。验收：v1 payload 下 P0 行为与现状一致。
- [ ] **Step 3: 固件触摸点按与命令通道（`…C04`）**：P2 点按工作单元发送 `{"action":"focus","slot":n}`。验收：Mac 端日志收到命令，旧固件无此 characteristic 时 Mac 不崩。
- [ ] **Step 4: 宠物主题**：AMOLED 黑底原创像素角色，8–12 fps，状态映射按设计第 6 节。验收：主题切换不改按键语义；资产为原创并在固件仓库注明来源。
- [ ] **Step 5: 熄屏待机 + BMI270 抬腕唤醒**：熄屏关 AMOLED/音频/马达电源轨，BLE 保活，IMU 手势中断唤醒。验收：抬腕识别率与误唤醒率实测记录；"仅点按唤醒"选项可用。
- [ ] **Step 6: 24h+ 功耗浸泡**：记录电量曲线、BLE 重连率、唤醒成功率，产出浸泡报告。

## Task 8: 端到端验证与报告

**Files:**
- Create: `docs/validation/2026-XX-XX-watch-v2-validation.md`

- [ ] **Step 1: 自动化全量**

```bash
swift package clean && swift build
bash scripts/test.sh
swift format lint --recursive --strict Sources Tests
bash scripts/privacy_scan.sh
bash scripts/package_app.sh
```

- [ ] **Step 2: 分层验证表**（沿用 v0.1 报告格式，状态只允许 PASS / FAIL / NOT VERIFIED）

必须覆盖的新层：v1/v2 协商与回退、多 provider 同步轮转、focus 命令闭环（点手表 → Codex Desktop 聚焦对应会话）、工作单元命名与淘汰、表盘设置即时下发、抬腕唤醒、24h 功耗浸泡。无真机/无固件时对应层标 NOT VERIFIED，不得由构建成功推断。

- [ ] **Step 3: 提交报告**

```bash
git add docs/validation
git commit -m "test: record watch v2 validation"
```

## 依赖顺序

```text
Task 1 (v2 模型) → Task 2 (协商) → Task 3 (命令通道+聚焦)  ┐
Task 4 (工作单元) ────────────────────────────────────────┤→ Task 5 (同步策略) → Task 6 (UI)
                                                          ┘
Task 7 (固件) 与 Mac 侧并行，经 capabilities 解耦；Task 8 最后。
```

Task 1–6 全部可用 fake transport 在无硬件条件下完成并测试；Task 7 需要固件仓库与 C152 真机。
