# TokenLink 表盘与协议 v2 架构图与时序图

状态：Mac/固件链路已在最终候选 C152 上验证；实体布局/触摸与长时功耗待验证

日期：2026-08-22

本文件是表盘 v2 设计文档的图解补充：一张系统架构图 + 三张关键时序图。
Mermaid 源码可直接在 GitHub / 支持 Mermaid 的 Markdown 查看器中渲染。

## 1. 系统架构图

```mermaid
flowchart TB
  subgraph External[外部服务与本机进程]
    KIMI["Kimi Code API<br/>api.kimi.com"]
    MM["MiniMax Token Plan API<br/>www.minimax.io / www.minimaxi.com"]
    GLMAPI["GLM Coding Plan API<br/>api.z.ai / open.bigmodel.cn"]
    CAS["Codex app-server<br/>本机 JSONL stdio 子进程"]
    CDESK["Codex Desktop"]
  end

  subgraph Mac["Mac：TokenLink.app（单进程）"]
    subgraph App[TokenLinkApp]
      UI["菜单栏 Popover / 管控中心<br/>表盘设置 · payload 预览"]
      AM["AppModel<br/>@MainActor 状态投影"]
      KV["KeychainVault<br/>凭据链：Keychain → CLI → env allowlist"]
      CS["ConfigurationStore<br/>config.json 原子写入"]
      WSP["WatchSyncPolicy<br/>纯函数：决定发 v1 / v2"]
      FH["FocusHandler<br/>激活 Codex Desktop"]
    end
    subgraph Prov[TokenLinkProviders]
      SPEC["ProviderSpec 注册表<br/>Kimi / MiniMax / GLM（声明式）"]
      COD["CodexProvider<br/>+ CodexWorkItemTracker"]
    end
    subgraph Core[TokenLinkCore]
      RC["RefreshCoordinator<br/>并发刷新"]
      PS["ProviderStore<br/>last-known-good / stale"]
      WI["WorkItemStore<br/>3 slot 命名工作单元"]
    end
    subgraph Dev[TokenLinkDevice]
      NEG["版本协商<br/>不支持则回退 v1"]
      PRJ["LegacyWatchProjection v1<br/>WatchProjectionV2"]
      BR["DeviceBridge<br/>绑定 / 连接 / 写确认"]
      CMD["命令通道解码<br/>focus(slot)"]
    end
  end

  subgraph Watch["TokenLink firmware/stopwatch-c152（C152）"]
    FACE["表盘页面<br/>P0 主页 · P1 额度 · P2 会话 · P3 系统"]
    PET["宠物主题（可选，默认关）"]
    INPUT["左右键 · 中央触摸盘 · 全屏滑动"]
    PWR["M5PM1 分级电源<br/>熄屏待机 · BMI270 抬腕唤醒"]
    BLES["BLE 栈（Bluedroid）"]
  end

  KIMI <-->|"HTTPS · host allowlist"| SPEC
  MM <-->|"HTTPS · host allowlist"| SPEC
  GLMAPI <-->|"HTTPS · host allowlist"| SPEC
  CAS <-->|"JSON-RPC over stdio"| COD
  SPEC --> RC
  COD --> RC
  COD -->|"会话事件 → 工作单元状态"| WI
  RC --> PS --> AM
  WI --> AM
  KV --> SPEC
  CS --> AM
  AM --> UI
  AM --> WSP
  NEG --> WSP
  WSP --> PRJ --> BR
  BR <-->|"GATT 私有服务<br/>C02 额度写 · C03 协商读"| BLES
  BLES -->|"C04 命令写"| CMD
  CMD --> AM
  AM --> FH --> CDESK
  INPUT -.->|"BLE HID 通道（PTT / Send / Voice Chat）"| CDESK
  BLES --- FACE
  FACE --- PET
  INPUT --> FACE
  PWR --- FACE
```

要点：

- **两条独立 BLE 通道**：HID 通道（按键 → Codex Desktop，存量行为不变）与
  私有 GATT 服务（额度 payload + 协商 + 命令通道）。
- **依赖方向固定**：`App → Providers → Core`、`App → Device → Core`，
  Providers 与 Device 互不依赖。
- **WatchSyncPolicy 是纯函数**：输入协商结果 + 各家快照 + 手表设置，输出
  下一条 payload，便于全量单测。
- 隐私边界：越过 BLE 的只有配额数字、工作单元短名/状态、slot 命令；
  凭据、账户、任务文本不出 Mac。

## 2. 时序图：启动刷新 → 版本协商 → 同步

```mermaid
sequenceDiagram
  autonumber
  participant AM as AppModel
  participant RC as RefreshCoordinator
  participant P as Providers（四家并发）
  participant PS as ProviderStore
  participant WSP as WatchSyncPolicy
  participant BR as DeviceBridge
  participant W as 手表固件

  AM->>RC: refreshAll()（启动 / 定时 / 手动 / 唤醒后）
  par 并发抓取，互不相阻塞
    RC->>P: Codex fetch()（app-server stdio）
    RC->>P: Kimi / MiniMax / GLM fetch()（HTTPS）
  end
  P-->>PS: QuotaSnapshot 或 ProviderFailure
  PS-->>AM: last-known-good + healthy / stale / error
  AM->>WSP: 输入协商结果 + 快照 + 手表设置
  alt 本连接尚未协商
    BR->>W: 读 capabilities（C03）
    alt 固件支持 v2
      W-->>BR: {"protocol_versions":[1,2]}
    else 不存在 / 超时 / 只认 v1
      BR-->>BR: 静默回退 v1（记录事件）
    end
  end
  alt 协商为 v2 且设置了多 provider
    BR->>W: 写 WatchPayloadV2（C02，with response）
  else v1 路径（默认仅 Codex）
    BR->>W: 写 LegacyWatchProjection（C02）
  end
  W-->>BR: ATT ACK
  BR-->>AM: synced(时间) / 失败进入退避
  Note over AM: UI 只展示快照真实新鲜度，<br/>失败不虚构实时值
```

## 3. 时序图：点按工作单元 → 激活 Codex Desktop

```mermaid
sequenceDiagram
  autonumber
  actor U as 用户
  participant W as 手表固件
  participant BR as DeviceBridge
  participant AM as AppModel
  participant WI as WorkItemStore
  participant FH as FocusHandler
  participant CD as Codex Desktop

  U->>W: 点按 P2 页的某个工作单元
  W->>BR: 写命令通道 C04：{"action":"focus","slot":1}
  BR->>AM: commandStream 产出 .focus(slot: 1)
  AM->>WI: 查 slot 1 对应的会话记录
  alt source == codex 且会话存在
    AM->>FH: focus(threadID)
    FH->>CD: 激活 Codex Desktop
    FH-->>AM: 记录完成事件
  else 非 Codex 来源 / 会话已不存在
    AM-->>AM: 记录事件，不向用户报错
  end
  Note over W,CD: 命令只带 slot 序号；thread ID 不进入事件或诊断。<br/>当前 app-server 不提供桌面线程选择方法
```

## 4. 时序图：熄屏待机与抬腕唤醒

```mermaid
sequenceDiagram
  autonumber
  actor U as 用户
  participant W as 固件主循环
  participant PM as M5PM1 电源管理
  participant IMU as BMI270
  participant BLE as BLE 栈
  participant Mac as TokenLink（Mac）

  Note over W: 无操作超时（电池 5 分钟 / 底座 30 分钟）
  W->>PM: 关闭 AMOLED / 音频 / 马达电源轨
  W->>IMU: 进入低功耗手势检测模式
  Note over BLE: 连接保活（modem sleep），<br/>仍能接收额度 payload
  Mac-->>BLE: 后台定期同步（不点亮屏幕）
  U->>IMU: 抬腕（或点按屏幕）
  IMU-->>W: IMU_INT 中断唤醒主控
  W->>PM: 打开 AMOLED 电源轨
  W->>W: 点亮并显示最后快照（过期则标 stale 灰显）
  BLE-->>W: 若有新 payload 立即更新页面
  Note over W,PM: 功耗档位与抬腕识别率以 24h+ 浸泡报告验收
```
