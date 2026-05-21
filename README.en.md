# PanBar

**A lightweight macOS menu bar app for live stock quotes and portfolio P&L.**
*macOS 菜单栏上的轻量盯盘工具 — 实时滚动自选股价格,一键查看持仓盈亏。*

[简体中文](README.md) · [English](README.en.md)

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![CI](https://github.com/TNT-Likely/PanBar/actions/workflows/ci.yml/badge.svg)](https://github.com/TNT-Likely/PanBar/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/TNT-Likely/PanBar?color=brightgreen&logo=github)](https://github.com/TNT-Likely/PanBar/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/TNT-Likely/PanBar/total?color=blue&logo=github)](https://github.com/TNT-Likely/PanBar/releases)

![Preview](docs/screenshots/preview.png)

---

## TL;DR

PanBar squeezes A-share / HK / US quotes into a tiny scrolling strip in the macOS menu bar. Click it for a compact 360pt panel showing your portfolio P&L, market indices, and price alerts — no window stealing, no cloud, no tracking.

## Features

- **Scrolling menu bar ticker** — pick which tickers to scroll, plus three summary metrics (today's P&L / total assets / lifetime P&L)
- **Multi-market** — A-share / HK / US in one place, **auto-aggregated by base currency (¥ / $ / HK$)**
- **Market indices** — 8 presets (SSE / SZSE / ChiNext / CSI300 / HSI / DJI / NDX / SPX), optionally shown in the ticker
- **Price alerts** — multi-condition (primary + secondary, AND/OR), daily trigger cap, trading-hours-only, weekdays-only
- **Configurable data sources** — Tencent / EastMoney / Yahoo / Finnhub, **per-market priority**
- **Stock search** — Chinese / pinyin / symbol, backed by Tencent smartbox
- **Privacy mode** — auto-masks the ticker during screen sharing or recording; ⌘⌃M to toggle manually
- **Color schemes** — Eastern (red-up / green-down), Western (green-up / red-down), or monochrome — switch live
- **Localization** — Simplified Chinese / English
- **Custom shortcuts** — global recorder, bind whatever you like
- **Full backup & restore** — one JSON contains all holdings / watchlist / alerts / settings
- **Fully local** — SQLite + cold-start FX cache · zero telemetry · zero cloud sync · zero ads

## Install

**Download the DMG** (Apple Developer ID notarized — Gatekeeper passes after a one-time "verified" prompt):

[**↓ Latest release**](https://github.com/TNT-Likely/PanBar/releases/latest) → double-click the `.dmg` → drag PanBar into Applications.

Or build from source:

```bash
brew install xcodegen create-dmg
git clone https://github.com/TNT-Likely/PanBar.git
cd PanBar
make run         # build & launch
```

## 💝 Donate

PanBar is fully free & open source — **no ads, no paid features**. If you find it useful, buy me a coffee ☕ to support ongoing development.

[![PayPal](https://img.shields.io/badge/PayPal-Donate-0070BA?logo=paypal&logoColor=white&style=for-the-badge)](https://paypal.me/sunxiaoyes)

Full options (Alipay / WeChat / USDT / Binance): **[💝 Donate page](https://github.com/TNT-Likely/BeeCount/blob/main/docs/donate/README_EN.md)**

> The link reuses the donate page of [BeeCount](https://github.com/TNT-Likely/BeeCount) by the same author — all channels kept up to date.

## License

MIT — see [LICENSE](LICENSE).
