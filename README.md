# PanBar

**macOS 菜单栏上的轻量盯盘工具** — 实时滚动自选股价格,一键查看持仓盈亏。

*A lightweight macOS menu bar app for live stock quotes and portfolio P&L.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)

---

## 为什么是 PanBar / Why PanBar

- **常驻菜单栏 / Always in menu bar** — 滚动展示价格和盈亏,不抢屏幕。
- **原生轻量 / Native & light** — SwiftUI + AppKit,内存占用 ~30MB,不是 Electron 套壳。
- **数据自选 / Bring your own data** — 腾讯 / 东方财富 / Yahoo / Finnhub,自由切换,无供应商锁定。
- **三市覆盖 / A / HK / US markets** — A 股、港股、美股一站式监控。

## 核心功能 / Features

| 功能 Feature | 说明 Description |
|---|---|
| 滚动行情 / Scrolling ticker | 菜单栏滚动展示价格、涨跌幅 |
| 持仓盈亏 / P&L | 点击弹窗查看总资产 / 今日盈亏 / 总盈亏 |
| 自选股 / Watchlist | 关注股票快速一览 |
| 大盘指数 / Indices | 沪指、深指、恒指、纳指、标普 |
| 价格预警 / Alerts | 涨跌幅 / 价格触发本地通知 |
| 交易时段感知 / Market hours | 自动识别开盘 / 休市状态 |

## 状态 / Status

项目初始化中,详见 [产品原型与交互设计 / Prototype & Interaction Design](docs/PROTOTYPE.md)。

## 技术栈 / Tech Stack

- **语言 Language**: Swift 5.9+
- **UI**: SwiftUI + AppKit (`NSStatusItem`)
- **最低系统 Min OS**: macOS 13 (Ventura)
- **分发 Distribution**: GitHub Release(开源)+ Mac App Store(后续)

## 路线图 / Roadmap

- **Phase 1 (MVP)** — 菜单栏滚动 + 持仓弹窗 + 多数据源
- **Phase 2** — 大盘指数 + 价格预警 + 多源 fallback
- **Phase 3** — CSV 导入 / 导出、深色模式定制、桌面小组件
- **Phase 4** — App Store 上架

## License

MIT
