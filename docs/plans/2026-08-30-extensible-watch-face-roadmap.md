# TokenLink 可扩展表盘路线图（0.3.x+）

状态：提案

日期：2026-08-30

涉及范围：TokenLink macOS 管控端 + 本仓库 `firmware/stopwatch-c152` C152 固件子树

## 1. 目标

从 0.3.x 开始，把当前写死的“数据 / 宠物”主题逐步重构为一个可扩展表盘系统：

- BLE 只传稳定、厂商无关的语义状态与受控命令；
- 固件提供受限的表盘运行时，数据表盘与宠物表盘走同一渲染接口；
- 表盘作者提交声明式 `.tokenface` 包，而不是固件代码或任意脚本；
- Mac 控制中心负责预览、校验、安装、启用、回滚和卸载；
- 先完成内部解耦，再开放本地导入，最后评估社区画廊。

这不是 0.2 协议 v2 的发布阻塞项。0.2 的 `data` / `pet` 设置和已有固件行为继续兼容，
0.3.x 通过 capability feature negotiation 渐进启用新能力。

0.2.1 已将匹配的 C152 固件迁入 TokenLink monorepo；0.3.x 的 Mac、协议、simulator 和
固件改动都在同一长期分支交付，不再依赖或发布外部固件仓库。

## 2. 长期架构边界

```text
Provider adapters
       │
       ▼
QuotaSnapshot / WorkItem
       │
       ▼
Canonical FaceState ── BLE state/command envelope ──► FaceRuntime
                                                         │
                         ┌───────────────────────────────┼──────────────┐
                         ▼                               ▼              ▼
                    data.tokenface                 pet.tokenface   user.tokenface
```

必须分别版本化三份契约：

1. **设备协议版本**：连接、状态更新、命令与兼容回退；
2. **FaceState schema**：表盘可绑定的语义数据，如额度、连接和工作单元状态；
3. **FaceRuntime / package schema**：固件能渲染的组件、动画、资源格式和动作。

“固定 BLE”指固定可扩展 envelope 和兼容规则，不是永远冻结某一份 JSON 字段。新增表盘能力
优先通过 capabilities 中的可选 feature 协商；只有无法保持兼容时才新增协议主版本。

## 3. 表盘包 v1 边界

建议扩展名为 `.tokenface`，内容为可校验的压缩目录：

```text
manifest.json
layout.json
states.json
assets/
preview.png
signature.json       # 官方/画廊分发时存在
```

package schema v1 只允许：

- 固件内置组件：文本、图片、进度条、状态图标和逐帧动画；
- 白名单数据绑定，例如 `quota.remaining`、`connection.state`、
  `work.latest.state`；
- 白名单动作，例如 `refresh`、`next_page`、`home` 和 `focus_slot`；
- 有上限的尺寸、颜色、帧数、帧率、总资源大小和页面数量。

package schema v1 明确不允许原生代码、Lua、JavaScript、网络请求、动态 BLE 访问、文件系统
访问或自定义 HID 指令。表盘包不能收到凭据、账户身份、prompt、任务全文或 Mac 内部 thread
ID。社区 review 因此聚焦于视觉、资产授权、资源预算和状态映射，而不是重新审计设备代码。

## 4. 版本路线

### 0.3.0 — 内部解耦，不开放第三方安装

目标：证明数据表盘与宠物表盘不再依赖两套专用分支。

Mac 端：

- 引入厂商无关的 `FaceState`，由现有 quota/work-item 状态投影生成；
- 将封闭的 `WatchFaceTheme` 迁移为开放的 `WatchFaceID`，旧配置中的 `data` / `pet`
  无损迁移；
- 保留现有 v2 `settings.theme` 兼容投影，不改变 v1 payload 的任何字节；
- 扩展 capabilities 的可选字段：`features`、`face_runtime_versions`、资源格式和容量上限；
- 把表盘选择、设备偏好和高频状态同步拆成独立模型，避免安装生命周期进入 quota payload。

固件端：

- 引入 `FaceRuntime`、组件树和内置表盘 registry；
- 数据 / 宠物两个内置表盘使用相同的状态绑定、输入动作和页面生命周期；
- 保留不可删除的数据表盘作为安全回退；
- 未报告新 feature 的 Mac 或固件继续使用当前 v2 行为。

验收：现有视觉与按键无回归，v1 字节兼容测试保持通过，v2 payload 仍满足当前 512-byte
上限，切换任一内置表盘不需要 renderer 中的主题特判。

### 0.3.1 — 包格式、校验器与桌面预览

目标：先稳定创作和 review 契约，不急于通过 BLE 安装。

- 冻结 `.tokenface` package schema v1 和 manifest 兼容规则；
- 把官方数据 / 宠物表盘转换为同格式的 reference packages；
- Mac 控制中心加入本地包导入与离线预览，但默认只允许预览；
- 预览正常、低额度、stale、离线、needs-input、完成等标准状态；
- 提供 validator，检查 schema、路径穿越、重复 ID、资源尺寸、动画预算、动作白名单和
  SHA-256；
- CI 为官方包渲染固定状态快照，便于视觉 diff 和人工 review。

验收：损坏或越权包在写入设备前被确定性拒绝；同一个官方包在 Mac 预览与固件 simulator
的关键布局一致；包格式文档和最小模板可以独立交给设计者使用。

### 0.3.2 — 设备安装生命周期（Beta）

目标：从控制中心安全安装、启用和回滚表盘。

- 新增独立 bulk-transfer characteristic 或等价二进制传输层，不复用 512-byte 状态
  payload；
- 使用 `begin → chunk → commit` 事务，带包大小、序号、SHA-256、超时、取消和断点清理；
- 固件先写 staging 区，完整校验后原子激活；断电、断连或校验失败保持原表盘；
- capabilities 报告安装支持、可用空间、最大包大小、运行时版本和资源格式；
- 控制中心提供“我的表盘”：安装、启用、设备兼容性、空间占用、卸载、恢复内置表盘；
- 官方包签名；未签名包只在明确开启的开发者模式中允许安装。

验收：中途断开 BLE、重复 chunk、错误 hash、空间不足和不兼容 runtime 都不会破坏当前
表盘；任何错误均可回退到内置数据表盘；安装与动画分别完成真机功耗和稳定性验证。

### 0.3.3 — 本地创作 Beta

目标：让小范围用户真正制作和分享表盘包，同时保持 review 可控。

- 发布 package schema、状态词典、资源预算和示例模板；
- 宠物表盘作为状态动画 reference，数据表盘作为低功耗 reference；
- 控制中心显示作者、许可证、签名、兼容性和包 hash；
- 导出可复现的 review bundle：manifest、validator 结果、标准状态截图和资产清单；
- 收集兼容性、安装失败、AMOLED 常亮像素和动画功耗数据，不收集表盘内容或用户状态。

验收：第三方作者无需修改或编译固件即可产出一个可预览、可验证、可本地安装的表盘；
review 不需要执行包内代码。

### 0.4.0+ — 社区画廊（单独决策）

公共画廊不与本地安装绑定发布。只有本地创作 Beta 稳定后，再评估：

- 提交、签名、审核、撤回和恶意包处置流程；
- 包 ID 所有权、版本更新、许可证与商标政策；
- 可复现构建和签名密钥治理；
- 控制中心内的官方基础款式与社区内容分区。

如果运营和审核成本不合适，0.3.x 的本地导入仍可作为完整、长期支持的终点。

## 5. 渐进重构顺序

每一步都应保持主分支可发布：

```text
现有 WatchSettings.theme
        │
        ├─► WatchFaceID + 旧值迁移
        │
        ├─► Canonical FaceState + v1/v2 compatibility adapters
        │
        ├─► Built-in FaceRuntime registry
        │
        ├─► Package loader / validator / preview
        │
        └─► BLE installer / storage / gallery
```

推荐先让旧 `data` / `pet` UI 通过 adapter 读取 `FaceState`，再移动渲染实现；不要同时改
状态模型、BLE 帧和视觉布局。安装传输与实时状态同步使用独立队列和重试策略，安装期间仍应
允许当前表盘继续显示最近状态。

## 6. 跨子树责任

| 责任 | Mac 模块（`Sources/`） | 固件（`firmware/stopwatch-c152/`） |
| --- | --- | --- |
| FaceState 生成与隐私投影 | 主责 | 只消费 |
| capabilities / 传输客户端 | 主责 | 实现服务端 |
| package validator 与预览 | 主责 | simulator 提供一致性样本 |
| FaceRuntime 与组件渲染 | 维护兼容模型 | 主责 |
| staging、校验、激活、回滚 | 发起并展示结果 | 主责 |
| 官方包资产与快照 | 共同 review | 共同 review |
| 真机触摸、功耗、断连测试 | 记录结果 | 执行与提供证据 |

## 7. 持续红线

- v1 payload 继续字节兼容；旧固件、旧 Mac 和未实现 package feature 的组合均能降级；
- 实时状态同步不得被大包安装饿死；
- 激活新包前必须完成结构校验、资源预算检查和整包 hash 校验；
- 永远保留可启动、不可删除的内置数据表盘；
- package/runtime/schema 分别版本化，未知字段可忽略，未知必需能力必须拒绝；
- 不把“可以本地安装”自动等同于“可以进入官方画廊”。

## 8. 分支与发布切点

长期实现分支为 `codex/watch-face-runtime-0.3`，始终基于当时最新的 `origin/main`
演进。为支持“做到哪里就发布到哪里”，提交历史遵循以下规则：

- 每个版本阶段先完成兼容 adapter、实现、测试和文档，再开始下一阶段；
- 阶段完成后保留明确的 milestone commit，不把不同阶段 squash 在一起；
- milestone 通过 Mac 自动化、固件 host-native 测试和对应真机验证后，再建立
  `codex/watch-face-runtime-0.3.x-ready` checkpoint 分支；
- 发布分支只合并最后一个完成的 checkpoint，不直接合并仍含下一阶段半成品的长期分支头；
- 未完成能力必须留在 capability feature 后面，默认关闭，不能改变已发布行为。

建议 checkpoint：

| Checkpoint | 可发布范围 |
| --- | --- |
| `0.3.0-ready` | FaceState、开放 FaceID、内置统一运行时，无第三方安装 |
| `0.3.1-ready` | 加 package schema、validator、官方包和桌面预览 |
| `0.3.2-ready` | 加设备安装、完整性校验、原子激活与回滚 Beta |
| `0.3.3-ready` | 加文档化的本地创作与分享 Beta |
