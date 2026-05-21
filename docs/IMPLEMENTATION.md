# PanBar 实现计划 Implementation Plan

> 版本: v0.1 · 状态: Draft · 最近更新: 2026-05-21

总工期估算:**5-6 周**(单人 / 兼职节奏);全职可压缩到 3 周。

---

## 0. 技术栈与依赖

| 项 | 选型 | 备注 |
|---|---|---|
| 语言 | Swift 5.9+ | 工具链 Xcode 15.4+ |
| 最低系统 | macOS 13 Ventura | 用 `SMAppService`、`NavigationStack` 等新 API |
| UI | SwiftUI + AppKit 桥接 | `NSStatusItem` 必须 AppKit |
| 持久化 | GRDB.swift 6.x | SQLite 封装,类型安全 + Combine/Async 支持 |
| 网络 | `URLSession` + Swift Concurrency | 不引入 Alamofire |
| 字符编码 | Foundation 内置 GBK | 腾讯/新浪接口需 |
| 日志 | `os.Logger` | 系统原生,免依赖 |
| 测试 | XCTest | Provider 用 stub URLProtocol |
| 构建脚本 | Makefile + xcodebuild | CI 友好 |
| 代码风格 | swift-format(Apple 官方) | pre-commit hook |
| 公证签名 | `notarytool` + Sparkle(后续更新) | App Store 上架后切换更新通道 |

**第三方依赖**(SPM):
- `groue/GRDB.swift`
- `apple/swift-async-algorithms`(用于节流 / 合并请求)
- `sparkle-project/Sparkle`(Phase 4 加,App Store 版可去掉)

---

## 1. 项目结构

```
PanBar/
├── PanBar.xcodeproj
├── PanBar/
│   ├── App/
│   │   ├── PanBarApp.swift          @main, AppDelegate 桥接
│   │   ├── AppDelegate.swift        生命周期 + NSStatusItem 注入
│   │   └── DependencyContainer.swift 简易 DI 容器
│   │
│   ├── MenuBar/
│   │   ├── StatusItemController.swift  NSStatusItem 管理
│   │   ├── TickerRenderer.swift        滚动文字渲染(NSAttributedString)
│   │   ├── TickerAnimator.swift        Timer 驱动的位移动画
│   │   └── ContextMenuBuilder.swift    右键菜单
│   │
│   ├── Popover/
│   │   ├── PopoverController.swift     NSPopover 持有
│   │   ├── Views/
│   │   │   ├── PopoverRoot.swift       SwiftUI 根视图
│   │   │   ├── SummaryCards.swift      三联卡
│   │   │   ├── HoldingsTab.swift
│   │   │   ├── WatchlistTab.swift
│   │   │   ├── IndicesTab.swift
│   │   │   └── AlertsTab.swift
│   │   └── ViewModels/
│   │       └── PopoverViewModel.swift  ObservableObject
│   │
│   ├── Settings/
│   │   ├── SettingsWindowController.swift
│   │   └── Panes/
│   │       ├── GeneralPane.swift
│   │       ├── TickerPane.swift
│   │       ├── PortfolioPane.swift
│   │       ├── DataSourcesPane.swift
│   │       ├── AlertsPane.swift
│   │       └── AboutPane.swift
│   │
│   ├── Domain/
│   │   ├── Models/
│   │   │   ├── Quote.swift             实时行情 DTO
│   │   │   ├── Holding.swift           持仓
│   │   │   ├── WatchItem.swift
│   │   │   ├── Alert.swift
│   │   │   ├── Market.swift            .a / .hk / .us 枚举
│   │   │   └── Currency.swift          .cny / .usd / .hkd
│   │   ├── Services/
│   │   │   ├── PortfolioService.swift  增删改 + 盈亏计算
│   │   │   ├── AlertEngine.swift       规则匹配 + 触发
│   │   │   ├── MarketClock.swift       交易时段判定
│   │   │   └── FXService.swift         汇率换算
│   │   └── Aggregates/
│   │       └── PortfolioSnapshot.swift 多币种汇总到本位币
│   │
│   ├── Data/
│   │   ├── Providers/
│   │   │   ├── QuoteProvider.swift     protocol
│   │   │   ├── TencentProvider.swift
│   │   │   ├── EastMoneyProvider.swift
│   │   │   ├── YahooProvider.swift     (Phase 3)
│   │   │   ├── FinnhubProvider.swift   (Phase 3)
│   │   │   └── CompositeProvider.swift 自动 fallback
│   │   ├── FX/
│   │   │   └── EastMoneyFXProvider.swift
│   │   ├── HTTP/
│   │   │   ├── HTTPClient.swift        URLSession 封装
│   │   │   └── GBKDecoder.swift
│   │   └── Persistence/
│   │       ├── Database.swift          GRDB 初始化
│   │       ├── Migrations.swift
│   │       └── Repositories/
│   │           ├── HoldingsRepository.swift
│   │           ├── WatchlistRepository.swift
│   │           ├── AlertsRepository.swift
│   │           ├── SettingsRepository.swift
│   │           └── FXCacheRepository.swift
│   │
│   ├── Infrastructure/
│   │   ├── Logger.swift
│   │   ├── LaunchAtLoginService.swift  SMAppService
│   │   ├── NotificationService.swift   UNUserNotificationCenter
│   │   ├── NetworkMonitor.swift        NWPathMonitor
│   │   ├── SleepMonitor.swift          NSWorkspace.willSleepNotification
│   │   └── I18n.swift                  本地化字符串助手
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets             图标、AppIcon
│   │   ├── Localizable.xcstrings       zh-Hans / en
│   │   └── Info.plist                  LSUIElement = YES(无 Dock 图标)
│   │
│   └── Generated/
│       └── (xcstrings 编译产物)
│
├── PanBarTests/
│   ├── Providers/
│   ├── Domain/
│   └── Fixtures/                      录制的 HTTP 响应样本
│
├── Makefile
├── README.md
├── LICENSE
└── docs/
```

---

## 2. 数据模型(精简)

```swift
struct Quote {
  let symbol: String           // "AAPL" / "600519"
  let market: Market           // .a / .hk / .us
  let name: String
  let price: Decimal
  let prevClose: Decimal
  let change: Decimal
  let changePct: Double        // 0.0062 -> 0.62%
  let currency: Currency
  let timestamp: Date
  let isClosed: Bool
}

struct Holding {
  let id: UUID
  let symbol: String
  let market: Market
  let quantity: Decimal
  let costPrice: Decimal
  let currency: Currency
  let note: String?
  let createdAt: Date
}

struct Alert {
  let id: UUID
  let symbol: String
  let market: Market
  let condition: AlertCondition  // .priceAbove / .priceBelow / .changePctAbove / .changePctBelow
  let threshold: Decimal
  let isActive: Bool
  let lastTriggeredAt: Date?
}

struct PortfolioSnapshot {
  let baseCurrency: Currency
  let totalAssets: Decimal
  let todayPnL: Decimal
  let todayPnLPct: Double
  let allTimePnL: Decimal
  let allTimePnLPct: Double
  let positions: [HoldingPosition]
}
```

---

## 3. 关键模块设计

### 3.1 QuoteProvider 协议(数据源抽象)

```swift
protocol QuoteProvider {
  var id: String { get }                          // "tencent" / "eastmoney"
  var supportedMarkets: Set<Market> { get }
  func fetch(_ symbols: [SymbolID]) async throws -> [Quote]
}

actor CompositeProvider: QuoteProvider {
  // 按市场维度查找首选源,失败按优先级链 fallback
  // 失败次数计数 + 冷却窗口,避免反复打死同一接口
}
```

### 3.2 TickerAnimator(滚动核心)

- 用 `Timer.publish(every: 1/60)` 驱动 60fps 位移
- 文字用 `NSAttributedString` 预渲染,避免重排
- 测量字符串宽度后,位移到末尾时 seamless 重置
- 监听 `NSWorkspace.willSleepNotification` 暂停

### 3.3 刷新调度

```swift
actor QuoteRefresher {
  enum Pace { case popoverOpen, tickerOnly, sleeping, marketClosed }
  // popoverOpen: 3s, tickerOnly: 5s, sleeping: paused, closed: 60s
}
```

### 3.4 AlertEngine

每次刷新行情后,遍历活跃 Alert → 匹配 → 触发 → 标记 `lastTriggeredAt` → 通过 `NotificationService` 发系统通知。
冷却时间默认 5 分钟,避免短时间内同条件反复触发。

---

## 4. Phase 切分 + 任务列表

### 🟥 Phase 1 — MVP (2 周, 约 60-80h)

**目标**:菜单栏能滚动 + Popover 能看持仓 + 数据真实可用

| # | 任务 | 估时 | 产出 |
|---|---|---|---|
| 1.1 | Xcode 项目初始化,LSUIElement,基础 entitlements | 2h | 可运行的空壳 |
| 1.2 | `NSStatusItem` + 静态图标(字母 P) | 2h | 菜单栏出现 P 图标 |
| 1.3 | `TickerRenderer` + `TickerAnimator` 滚动 | 6h | 写死的文字能滚 |
| 1.4 | `HTTPClient` + `GBKDecoder` | 4h | 能拉腾讯接口的字符串 |
| 1.5 | `TencentProvider` 实现 + 解析 | 6h | 真实股价能滚动 |
| 1.6 | `EastMoneyProvider` 实现 | 5h | 同上 |
| 1.7 | `CompositeProvider` fallback 逻辑 | 3h | 单源挂自动切换 |
| 1.8 | GRDB 集成 + 迁移 | 4h | Holdings 表能持久化 |
| 1.9 | `HoldingsRepository` + `PortfolioService` | 5h | CRUD + 盈亏计算 |
| 1.10 | `EastMoneyFXProvider` + `FXService` + 缓存 | 4h | 汇率拉取与本地缓存 |
| 1.11 | `PopoverController` + `PopoverRoot` SwiftUI | 6h | 点击图标弹窗 |
| 1.12 | `SummaryCards` + `HoldingsTab` UI | 8h | 与原型 HTML 一致 |
| 1.13 | `WatchlistTab` UI + Repository | 5h | 自选股增删 |
| 1.14 | `MarketClock` 交易时段判定 | 3h | 休市状态正确 |
| 1.15 | 简易 Settings 窗口(只 General + Portfolio) | 6h | 能加股票 |
| 1.16 | `QuoteRefresher` 节流调度 | 4h | 不同状态不同频率 |
| 1.17 | `LaunchAtLoginService` | 1h | 开机启动 |
| 1.18 | 中英文本地化(`xcstrings`) | 3h | 双语切换 |
| 1.19 | 端到端联调 + bug 修 | 6h | 可日用 |
| **合计** | | **83h** | **v0.1.0-alpha** |

**MVP 完成判定** = `docs/FEATURES.md` 的"验收标准"全部勾选。

---

### 🟧 Phase 2 — 增强 (1.5 周, 约 40h)

| # | 任务 | 估时 |
|---|---|---|
| 2.1 | `IndicesTab`(预置 7 个指数) | 6h |
| 2.2 | `AlertsTab` + `AlertEngine` + `NotificationService` | 10h |
| 2.3 | Settings → Ticker 页(速度 / 模板 / 配色) | 6h |
| 2.4 | Settings → Alerts 页 | 4h |
| 2.5 | CSV 导入导出 | 5h |
| 2.6 | 右键菜单 + 上下文菜单 | 3h |
| 2.7 | `NetworkMonitor` + `SleepMonitor` 智能暂停 | 4h |
| 2.8 | 性能优化(请求合并 + 节流) | 4h |

---

### 🟨 Phase 3 — 体验完善 (1 周, 约 30h)

| # | 任务 | 估时 |
|---|---|---|
| 3.1 | Onboarding 引导流程 | 6h |
| 3.2 | `YahooProvider` + `FinnhubProvider`(用户填 Key) | 6h |
| 3.3 | Data Sources 设置页 + 优先级拖拽 | 5h |
| 3.4 | 主题 + 视觉密度切换 | 4h |
| 3.5 | 全局快捷键 | 3h |
| 3.6 | 浏览器跳转 URL 模板 | 2h |
| 3.7 | 单元测试覆盖率到 60%+ | 4h |

---

### 🟦 Phase 4 — 发布 (1 周, 约 25h)

| # | 任务 | 估时 |
|---|---|---|
| 4.1 | App Icon 完整设计(字母 P,各尺寸) | 4h |
| 4.2 | Developer ID 签名 + `notarytool` 公证 | 3h |
| 4.3 | Sparkle 集成(GitHub Release 自动更新) | 4h |
| 4.4 | GitHub Actions:tag → build → notarize → release | 5h |
| 4.5 | 隐私政策 + 主页(简单 GitHub Pages) | 3h |
| 4.6 | App Store 准备(截图、描述、审核合规版去 Sparkle) | 6h |

---

## 5. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| 腾讯/东财接口反爬封 IP | ⭐⭐⭐ 数据断流 | 多源 fallback + 节流 + 用户 UA 轮换 |
| App Store 审核拒绝(数据源未授权) | ⭐⭐⭐ 上架受阻 | App Store 版默认要求用户填 Finnhub Key |
| 菜单栏 ticker 性能 / 渲染卡顿 | ⭐⭐ 体验差 | NSAttributedString 预渲染 + 限制最大字符数 |
| FX 汇率不准 / 接口挂 | ⭐⭐ 汇总数字偏 | 本地缓存 + 失败显示 "--" 不阻塞主流程 |
| GBK 解码 bug(腾讯) | ⭐ 中文乱码 | `String(data:encoding:)` 用 .init(rawValue: 0x80000632) |
| macOS 13 之前的用户提需求 | ⭐ 兼容投诉 | README 明确写 min OS,不向下兼容 |

---

## 6. 第一周冲刺清单(可立即开始)

按以下顺序开干,每天 4-6h:

**Day 1**
- [ ] Xcode 项目初始化 / Git init / .gitignore
- [ ] LSUIElement = YES(无 Dock 图标)
- [ ] `NSStatusItem` 显示静态 P 图标
- [ ] Makefile:`make build` / `make run`

**Day 2**
- [ ] `HTTPClient` + `GBKDecoder`
- [ ] `TencentProvider` 单元测试用 fixture 跑通
- [ ] CLI 手测拉一只 AAPL 出 JSON 打印

**Day 3**
- [ ] `TickerRenderer` 把 5 只股票拼成 NSAttributedString
- [ ] `TickerAnimator` 60fps 滚动
- [ ] 接 Provider,菜单栏滚动真实数据

**Day 4**
- [ ] GRDB 集成 + Migration v1(holdings 表)
- [ ] `HoldingsRepository` CRUD
- [ ] `PortfolioService.calculate()` 单元测试

**Day 5**
- [ ] `PopoverController` + 空 SwiftUI 根视图
- [ ] `SummaryCards` 静态数据先跑通

**Day 6-7**
- [ ] `HoldingsTab` + 真实数据接入
- [ ] `EastMoneyFXProvider` + FX 换算
- [ ] Summary 数字与原型一致

→ 周末出第一个能演示的 demo 视频。

---

## 7. 开发约定

- 分支策略:`main`(可发布)+ `dev`(集成)+ `feature/*`
- Commit 风格:`<type>: <subject>` 同 PanWatch 仓约定
- PR 必须过 `xcodebuild test`
- 每个 Phase 结束打 tag:`v0.1.0-alpha`、`v0.2.0-beta`、`v1.0.0`
- 所有 UI 字符串必须走 `Localizable.xcstrings`,禁止硬编码
- Provider 必须有对应的 fixture 测试(录制 HTTP 响应回放)
