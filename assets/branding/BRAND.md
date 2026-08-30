# TokenLink 品牌视觉体系 v0.2

TokenLink 的视觉核心概念是 **“仪表盘 × 链接”**：圆弧进度表代表 AI 编程额度，开口的链环代表 Mac 与 M5Stack StopWatch 之间的 BLE 连接。

## 色彩

| 用途 | 色值 | 说明 |
| --- | --- | --- |
| 背景（深） | `#0B1220` | 深青 slate，所有暗色物料的底色 |
| 主色 / 信号青 | `#00C2A8` | 健康额度、BLE 链路、品牌强调 |
| 警示琥珀 | `#F5A623` | 低额度 / 即将耗尽状态 |
| 文字主色 | `#FFFFFF` | 标题 |
| 供应商点缀 | 绿 / 蓝 / 紫 / 橙 | 四家 Provider 的抽象代表色，非官方品牌色 |

## 素材清单

| 文件 | 用途 |
| --- | --- |
| `logo-mark-dark.png` (1024×1024) | 主标志，用于深色背景，并作为 App 图标源文件 |
| `logo-mark-light.png` (1024×1024) | 浅色背景、README 和文档用标志 |
| `../../packaging/TokenLink.icns` | macOS Finder、通知与应用元数据使用的正式图标 |
| `banner-hero.png` (1280×720) | README 顶部横幅 |
| `social-preview.png` (1280×640) | GitHub 仓库 Social Preview（Settings → General 上传） |
| `../video/tokenlink-promo.mp4` (25s, 720p) | 宣传短片成片 |
| `../video/raw/clip1-4.mp4` | 分镜素材，可单独用于 GIF/短剪辑 |
| `../video/endcard.png` | 片尾卡静帧，可作通用封面 |

## 宣传片分镜

1. **clip1 (0:00–5:30)** 菜单栏额度面板特写 —— 一屏看尽
2. **clip2 (5:30–11:00)** 四色光球汇聚为青色节点 —— 四家 Provider 一处聚合
3. **clip3 (11:00–16:30)** 青色光束从 MacBook 射向桌面小设备 —— BLE 同步
4. **clip4 (16:30–22:00)** 设备圆屏显示 72% 剩余额度 —— 抬眼即见
5. **endcard (22:00–25:00)** Logo + TokenLink + *Your AI quota, at a glance.*

## 使用约定

- 不要旋转、拉伸或改色；缩放时始终保持正方形比例。
- 深色物料优先使用 `logo-mark-dark.png`；浅底文档使用 `logo-mark-light.png`。
- 菜单栏小图标继续使用单色 template 图形，不直接缩放彩色 App 图标。
- 视频中不出现真实供应商商标，仅用四色光球抽象指代。
- `packaging/TokenLink.icns` 可通过 `bash scripts/generate_app_icon.sh` 从深色主标志重新生成。
