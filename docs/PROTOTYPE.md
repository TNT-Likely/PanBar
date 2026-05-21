# PanBar 产品原型与交互设计

> 版本: v0.1 · 状态: Draft · 最近更新: 2026-05-21

---

## 0. 一句话定位

**PanBar 是一个常驻 macOS 菜单栏的轻量股票工具,在屏幕顶部滚动展示自选/持仓的实时价格,点击菜单栏图标弹出紧凑的盈亏面板。**

设计哲学:
- **Glanceable first** — 不打开 App 也能看到关键信息。
- **Zero distraction** — 不发推送、不抢焦点、不弹窗,除非用户主动设置预警。
- **Native macOS** — 完全符合 HIG,菜单栏 + Popover 是首选交互,不做大窗口。

---

## 1. 信息架构

```
PanBar
├── 菜单栏 (NSStatusItem)
│   ├── 滚动条:股票代码 / 价格 / 涨跌幅
│   ├── 左键点击 → Popover 主面板
│   └── 右键点击 → 快捷菜单(暂停滚动 / 刷新 / 设置 / 退出)
│
├── Popover 主面板 (~ 360 × 520pt)
│   ├── Header:Logo + 名称 + 设置齿轮 + 关闭
│   ├── Summary 区:总资产 / 今日盈亏 / 总盈亏
│   ├── Tabs:Holdings | Watchlist | Indices | Alerts
│   ├── 内容区:对应 Tab 的列表
│   └── Footer:刷新按钮 + 上次更新时间 + 版本号 + Quit
│
└── 设置窗口 (Settings Window, 独立 NSWindow)
    ├── General        通用(开机启动 / 主题 / 语言)
    ├── Ticker         滚动设置(速度 / 显示字段 / 涨跌配色)
    ├── Portfolio      持仓管理(增删改 / CSV 导入导出)
    ├── Data Sources   数据源(腾讯/东财/Yahoo/Finnhub + API Key)
    ├── Alerts         价格预警规则
    └── About          关于 / 版本 / 反馈链接
```

---

## 2. 菜单栏形态(核心交互)

### 2.1 显示模板

可配置展示模板,支持变量插值:

```
{symbol} {price} {change_pct}
```

例:`AAPL 195.50 +0.62%`,多只股票之间用 `  ·  ` 分隔。

模板预设:

| 预设 | 模板 | 示例 |
|---|---|---|
| Compact | `{symbol} {change_pct}` | `AAPL +0.62%` |
| Standard | `{symbol} {price} {change_pct}` | `AAPL 195.50 +0.62%` |
| Detailed | `{name} {price} {change_pct} {pnl}` | `Apple 195.50 +0.62% +$120` |

### 2.2 滚动行为

- **方向**: 从右向左匀速滚动(经典 ticker tape)
- **速度**: 慢 / 中 / 快 三档,默认中(约 30px/s)
- **暂停**: 鼠标 hover 菜单栏文字时自动暂停,移开后恢复
- **循环**: 滚完最后一只票后无缝衔接第一只,中间用 `  ·  ` 分隔
- **休市态**: 检测到当前市场休市时,文字变灰,滚动减速到 1/3,提示"Closed"

### 2.3 涨跌配色

| 模式 | 涨 | 跌 |
|---|---|---|
| **East**(默认,A/HK)| 红色 `#E74C3C` | 绿色 `#27AE60` |
| **West**(US 默认)| 绿色 `#27AE60` | 红色 `#E74C3C` |
| **Monochrome** | 加粗 + ▲ | 加粗 + ▼ |

用户可在 Settings → Ticker 切换。

### 2.4 多市场轮播策略

如果用户同时关注 A 股、港股、美股,且时区分散:
- **自动模式**: 只滚动当前开盘市场的股票,休市市场折叠为静态"AAPL 195.50 [closed]"
- **手动模式**: 全部滚动,无视交易时段

### 2.5 右键快捷菜单

```
⏸  Pause Scrolling
↻  Refresh Now            ⌘R
─────────────────────
   Show Popover           ⌘P
   Open Settings…         ⌘,
─────────────────────
   About PanBar
   Quit PanBar            ⌘Q
```

---

## 3. Popover 主面板

### 3.1 视觉风格

参考 Claude God 的紧凑卡片式布局:
- 圆角卡片 + 细分隔线
- 系统默认字体;Popover 内列表的数字列用 `.monospacedDigit()` 修饰符做"等宽数字"对齐(不切换字体家族,仅数字字形等宽)
- 涨绿跌红用色块标识(不光是文字色)
- 整体宽度 360pt,自适应高度 480-560pt

### 3.2 布局示意(ASCII 草图)

```
┌─────────────────────────────────────────┐
│  📊  PanBar                    ⚙  ⨯    │  ← Header
├─────────────────────────────────────────┤
│  TOTAL ASSETS                            │
│  $48,250.30                              │  ← Summary
│  Today  +$120.50 (+0.25%)               │
│  All-Time  +$8,420.10 (+21.13%)         │
├─────────────────────────────────────────┤
│ [Holdings] Watchlist  Indices  Alerts   │  ← Tabs
├─────────────────────────────────────────┤
│  AAPL   Apple                            │
│  195.50  +0.62%   100sh   +$120.50      │
│ ─────────────────────────────────────── │
│  TSLA   Tesla                            │
│  245.20  -1.45%    50sh   -$180.00      │
│ ─────────────────────────────────────── │
│  600519 贵州茅台                          │
│  1685.00 +0.85%    10sh   +¥140.00      │
├─────────────────────────────────────────┤
│  ↻ Updated 2s ago        v0.1.0   Quit  │  ← Footer
└─────────────────────────────────────────┘
```

### 3.3 Tab 详细设计

#### Tab 1: Holdings(持仓,默认)

每行展示:代码 / 名称 / 现价 / 涨跌幅 / 持仓数 / 盈亏金额(原币种)

**多币种汇总**:Summary 区的"总资产 / 今日盈亏 / 总盈亏"按用户设定的**本位币**(默认 CNY,可切 USD / HKD)统一换算展示;单行明细仍保留原币种(避免视觉错乱)。汇率源参见 §4.4。

- 单击一行 → 展开二级信息(成本价、市值、持仓占比、今日盈亏、换算到本位币后的金额)
- 双击一行 → 浏览器打开(默认目标:雪球 / Yahoo,可在设置切换)
- 长按或右键 → 上下文菜单(编辑持仓 / 删除 / 设置预警)

空态:"No holdings yet. [+ Add Position]"

#### Tab 2: Watchlist(自选股)

只显示行情,不计算盈亏。布局更紧凑(单行)。
- 拖拽排序
- 右键 → "Move to Holdings"(转为持仓,弹出输入成本价的对话框)

#### Tab 3: Indices(大盘)

预置卡片:沪指、深指、创业板、恒指、纳指、标普、道指。用户可在设置勾选显示哪些。

#### Tab 4: Alerts(预警)

最近触发的预警列表:
```
🔔 AAPL above $200          2 min ago
🔔 TSLA down 5% today       1 hour ago
🔕 600519 below ¥1600       yesterday (snoozed)
```

点击 + 添加预警规则,弹出对话框选择标的、条件、阈值。

---

## 4. 设置窗口

独立的 `NSWindow`(不是 Popover),分 Tab(类似 macOS 系统设置):

### 4.1 General

- ☑ Launch at login(开机启动,通过 `SMAppService`)
- Theme:System / Light / Dark
- Language:Auto / 简体中文 / English
- **Base Currency:Auto / CNY / USD / HKD**(影响 Popover Summary 的汇总换算)
- Update channel:Stable / Beta

### 4.2 Ticker

- Display template(下拉:Compact / Standard / Detailed / Custom)
- Scroll speed(滑块:Slow ←→ Fast)
- Color scheme(East / West / Monochrome)
- ☑ Pause on hover
- ☑ Auto-pause when market closed
- Max items in ticker(默认 10,避免菜单栏占太长)

### 4.3 Portfolio

持仓表格,字段:Symbol / Market / Quantity / Cost Price / Currency / Note

操作:
- `+` 添加
- `-` 删除
- `↑` 导入 CSV
- `↓` 导出 CSV

CSV 格式:`symbol,market,quantity,cost_price,currency,note`

### 4.4 Data Sources

| Source | Markets | Auth | Status |
|---|---|---|---|
| Tencent (qt.gtimg.cn) | A / HK / US | None | ✓ Built-in |
| EastMoney (push2) | A / HK / US + **FX** | None | ✓ Built-in |
| Yahoo Finance | US / Global | None | ✓ Built-in |
| Finnhub | US | API Key | ☐ Configure |
| Alpha Vantage | Global | API Key | ☐ Configure |

**FX 汇率源**:默认走 EastMoney 外汇接口(`USDCNH` / `HKDCNH` 等),每 5 分钟刷新一次,缓存到本地。汇率获取失败时,Holdings 的换算列显示 `--`,不阻塞主流程。

每个市场可设置首选源 + Fallback 链(拖拽排序)。

### 4.5 Alerts

预警规则表:
| Symbol | Condition | Threshold | Notify | Active |
|---|---|---|---|---|
| AAPL | Price ≥ | 200 | macOS Notification | ☑ |
| TSLA | Change % ≤ | -5 | macOS Notification + Sound | ☑ |

通知方式:仅本地系统通知(MVP 阶段不接 Telegram / 邮件)。

### 4.6 About

- App 版本 / Swift 版本 / 构建时间
- GitHub 链接 / 报告 Bug
- License / 致谢(开源库列表)

---

## 5. 数据刷新策略

| 状态 | 刷新间隔 | 说明 |
|---|---|---|
| Popover 打开中 | 3 秒 | 用户正在看,高频刷新 |
| 仅菜单栏滚动 | 5 秒 | 平衡新鲜度与请求频率 |
| 系统休眠 / 屏幕锁定 | 暂停 | 监听 `NSWorkspace` 通知 |
| 网络断开 | 暂停 + 灰色显示"offline" | 监听 `NWPathMonitor` |
| 市场休市 | 60 秒 | 偶尔刷,但不浪费请求 |

请求合并:同一市场的所有 symbol 用一次批量接口拉取(腾讯/东财都支持)。

---

## 6. 关键交互流程

### 6.1 首次启动流程

1. App 启动 → 检测是否首次运行
2. 引导窗口(三步):
   - Step 1:Welcome,简介 PanBar 能做什么
   - Step 2:Add your first stock(快速搜索 + 添加)
   - Step 3:Choose color scheme(East / West)
3. 引导完成 → 关闭窗口,进入菜单栏常驻态

### 6.2 添加持仓流程

1. Popover → Holdings Tab → "+ Add Position" 按钮
2. 弹出 Sheet:
   - 搜索框(输入代码 / 名称,实时查询)
   - 选中后填写:Quantity / Cost Price / 备注
3. 保存 → 立即出现在 Holdings 列表,菜单栏滚动加入该 symbol

### 6.3 触发预警流程

1. 后台轮询发现条件满足
2. 发送 macOS 本地通知(`UNUserNotificationCenter`)
3. 通知点击 → 打开 PanBar Popover → 跳到 Alerts Tab
4. 该预警进入"已触发"状态(避免每次刷新都通知)
5. 用户可"Snooze 1h" / "Disable" / "Reset"

---

## 7. MVP 切分

| Phase | 范围 | 预估工期 |
|---|---|---|
| **Phase 1 (MVP)** | 菜单栏滚动 + Popover Holdings + Watchlist + 腾讯数据源 + 设置基础 | 2 周 |
| **Phase 2** | 大盘指数 Tab + 价格预警 + 多数据源 fallback + CSV 导入导出 | 1.5 周 |
| **Phase 3** | 引导流程 + 国际化(中/英)+ 主题定制 + 性能优化 | 1 周 |
| **Phase 4** | 公证签名 + GitHub Release + App Store 上架 | 1 周 |

---

## 8. 已确认的设计决策

- ✅ **加密货币**:v1 **不做**,聚焦股票场景,降低数据源依赖与维护成本
- ✅ **多币种汇总**:**做**统一本位币换算(默认 CNY,可在设置切换 USD / HKD)。需要引入 FX 数据源(优先使用 EastMoney 外汇接口免费、稳定)
- ✅ **菜单栏字体**:**系统默认字体**(`NSFont.menuBarFont(ofSize:)`),不强制等宽。理由:节省菜单栏宽度,与 macOS 原生 UI 一致;Popover 内部数字仍可考虑等宽对齐
- ✅ **图标设计**:**字母 P** 单字图标
  - 菜单栏图标:模板图(template image)版本,自动适配亮/暗模式
  - App Icon:加底色 + 微立体效果,保持识别度
  - 风格参考:Notion / Linear / Raycast 的单字母 logo

## 9. 仍待决策事项

- [ ] **付费策略**:开源免费 + App Store 上架免费 + 未来 Pro 版?(参考 Raycast 模式)
- [ ] **隐私声明**:不上报任何用户数据,需要在 App 内显示并写入隐私政策
- [ ] **本位币默认值**:首次启动时根据系统区域自动选(中国 → CNY,US → USD)?

---

## 附录 A:屏幕尺寸适配

- MacBook Air 13" (1440×900):菜单栏宽度约 1100pt 可用,ticker 限制最多滚动 ~80 字符
- 4K 外接显示器:无限制
- 检测策略:监听 `NSScreen.main` 变化,动态调整滚动文字最大长度

## 附录 B:键盘快捷键

| 快捷键 | 动作 |
|---|---|
| ⌘P | Show/Hide Popover |
| ⌘R | Refresh Now |
| ⌘, | Open Settings |
| ⌘Q | Quit |
| ⌘1-4 | Switch Tabs(Popover 内) |
| ⌘F | Search in Holdings(Popover 内) |
