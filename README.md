# PanBar

**macOS 菜单栏上的轻量盯盘工具** — 实时滚动自选股价格,一键查看持仓盈亏。
*A lightweight macOS menu bar app for live stock quotes and portfolio P&L.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![CI](https://github.com/TNT-Likely/PanBar/actions/workflows/ci.yml/badge.svg)](https://github.com/TNT-Likely/PanBar/actions/workflows/ci.yml)

![Preview](docs/screenshots/preview.png)

---

## 一句话 / TL;DR

PanBar 把 A / 港 / 美三市行情塞进 macOS 菜单栏的一小条滚动文字里。点开 360pt 的紧凑面板看持仓盈亏、大盘指数、价格预警 — 不抢屏幕、不挂网络、不收集任何数据。

PanBar squeezes A-share / HK / US quotes into a tiny scrolling strip in the macOS menu bar. Click it for a compact 360pt panel showing your portfolio P&L, market indices, and price alerts — no window stealing, no cloud, no tracking.

## 功能 / Features

- **菜单栏滚动 ticker** — 自定义勾选要滚动的股票 + 三大汇总指标(今日盈亏 / 总资产 / 累计)
- **多市场覆盖** — A / 港 / 美一站式,**自动按本位币(¥ / $ / HK$)汇总**
- **大盘指数** — 8 个预置(沪指 / 深成 / 创业板 / 沪深300 / 恒生 / 道琼斯 / 纳指 / 标普),可选择性显示在 ticker 里
- **价格预警** — 多条件(主+副,AND/OR)、每日触发次数上限、仅交易时段、仅工作日
- **数据源可配** — 腾讯 / 东方财富 / Yahoo / Finnhub,**每市场独立优先级**
- **股票搜索** — 中文 / 拼音 / 代码,直连腾讯 smartbox
- **隐私模式** — 屏幕共享/录屏时自动遮蔽 ticker;⌘⇧M 手动一键切换
- **配色方案** — 东方红涨绿跌 / 西方绿涨红跌 / 黑白单色,实时切换
- **多语言** — 简体中文 / English
- **可自定义快捷键** — 全局录入器,你想用啥按啥
- **全量备份恢复** — 一个 JSON 文件包含全部持仓 / 自选 / 预警 / 设置
- **完全本地** — SQLite + 启动期 FX 缓存 · 无埋点 · 无云同步 · 无广告

## 安装 / Install

> **正式 Release 还在路上**(需要 Apple Developer ID 公证签名),目前请从源码构建:

```bash
brew install xcodegen create-dmg
git clone https://github.com/TNT-Likely/PanBar.git
cd PanBar
make run         # 一键构建 + 启动
```

## 截图 / Screenshots

可视化原型(浏览器打开):[`docs/mockups/prototype.html`](docs/mockups/prototype.html)

完整功能与交互说明:[`docs/PROTOTYPE.md`](docs/PROTOTYPE.md) · [`docs/FEATURES.md`](docs/FEATURES.md)

## 技术栈 / Tech Stack

Swift 5.9+ / SwiftUI + AppKit(`NSStatusItem`)/ GRDB.swift / Sparkle / Carbon hotkey / macOS 13+

## 数据源 / Data Sources

| Source | Markets | 鉴权 |
|---|---|---|
| 腾讯财经 / Tencent | A / HK / US | None |
| 东方财富 / EastMoney | A / HK / US + FX | None |
| Yahoo Finance | A / HK / US | None |
| Finnhub | US | API Key |

设置 → 数据源 里可拖排序、单独启用,失败自动 30 秒冷却 fallback。

## 文档 / Docs

| 文档 | 内容 |
|---|---|
| [PROTOTYPE.md](docs/PROTOTYPE.md) | 产品原型 + 交互设计 |
| [FEATURES.md](docs/FEATURES.md) | MoSCoW 功能清单 + 验收标准 |
| [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | 实现计划(任务级,P1-P4) |
| [RELEASING.md](docs/RELEASING.md) | 签名 / 公证 / Sparkle / GitHub Actions |
| [APPSTORE.md](docs/APPSTORE.md) | App Store 上架准备 |
| [PRIVACY.md](PRIVACY.md) | 隐私政策(中英双语) |

## 隐私 / Privacy

零追踪 / 零云同步 / 无广告 — 详见 [PRIVACY.md](PRIVACY.md)。

## License

MIT — see [LICENSE](LICENSE).
