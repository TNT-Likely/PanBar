# PanBar

**macOS 菜单栏上的轻量盯盘工具** — 实时滚动自选股价格,一键查看持仓盈亏。

*A lightweight macOS menu bar app for live stock quotes and portfolio P&L.*

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS%2013%2B-black?logo=apple)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange?logo=swift)](https://swift.org)
[![CI](https://github.com/TNT-Likely/PanBar/actions/workflows/ci.yml/badge.svg)](https://github.com/TNT-Likely/PanBar/actions/workflows/ci.yml)

---

## 为什么是 PanBar / Why PanBar

- **常驻菜单栏 / Always in menu bar** — 滚动展示价格和盈亏,不抢屏幕。
- **原生轻量 / Native & light** — SwiftUI + AppKit,~30MB 内存,不是 Electron 套壳。
- **数据自选 / Bring your own data** — 腾讯 / 东方财富 / Yahoo / Finnhub,优先级可配,无供应商锁定。
- **三市覆盖 / A / HK / US markets** — A 股、港股、美股一站式监控,自动按本位币汇总。
- **零追踪 / Zero tracking** — 无埋点、无广告、无云同步,数据从不离开你的 Mac。

## 核心功能 / Features

| 功能 Feature | 说明 Description |
|---|---|
| 滚动行情 / Scrolling ticker | 菜单栏自定义滚动价格、涨跌幅,hover 暂停 |
| 持仓盈亏 / P&L | 今日 / 累计盈亏按本位币(¥ / $ / HK$)统一汇总 |
| 自选股 / Watchlist | 关注股票快速一览 |
| 大盘指数 / Indices | 沪指 / 深成指 / 创业板 / 沪深300 / 恒生 / 纳指 / 标普 / 道指 |
| 价格预警 / Alerts | 涨跌触发本地通知,带冷却避免轰炸 |
| 涨跌配色 / Color scheme | East 红涨绿跌 · West 绿涨红跌 · Mono 黑白 |
| 全局快捷键 / Global hotkey | ⌘⇧P 任意位置唤起面板 |
| CSV 导入导出 / CSV | 持仓 + 自选独立 CSV |
| 数据源优先级 / Provider priority | 每市场独立配置,失败 30s 冷却 |
| 自动更新 / Auto-update | Sparkle EdDSA 签名,后台静默检查 |
| 中英双语 / zh-Hans + en | 完整本地化 |

## 安装 / Install

下载最新 Release:

- **DMG**(推荐):<https://github.com/TNT-Likely/PanBar/releases/latest>
- **从源码构建**:见下方"开发"章节

> 第一次启动 macOS 会询问是否打开未签名/未公证的版本。正式 Release 已公证,正常双击即可。

## 开发 / Development

依赖:

- Xcode 15.4+
- macOS 13+
- `brew install xcodegen` (项目用 xcodegen 管理)

```bash
git clone https://github.com/TNT-Likely/PanBar.git
cd PanBar
make open         # 在 Xcode 中打开,或:
make run          # 直接构建并启动
```

更多构建目标:

```bash
make help         # 列出所有可用目标
make icons        # 重新生成 AppIcon
make release-build VERSION=0.1.0   # Release 构建
make dmg VERSION=0.1.0             # 打包 DMG(需 create-dmg)
```

完整发布流程见 [`docs/RELEASING.md`](docs/RELEASING.md)。

## 项目文档 / Project Docs

| 文档 | 内容 |
|---|---|
| [PROTOTYPE.md](docs/PROTOTYPE.md) | 产品原型与交互设计 |
| [FEATURES.md](docs/FEATURES.md) | MoSCoW 功能清单 + 验收标准 |
| [IMPLEMENTATION.md](docs/IMPLEMENTATION.md) | 实现计划(P1-P4 任务级) |
| [RELEASING.md](docs/RELEASING.md) | 签名 / 公证 / Sparkle / GitHub Actions |
| [APPSTORE.md](docs/APPSTORE.md) | App Store 上架准备 |
| [PRIVACY.md](PRIVACY.md) | 隐私政策(双语) |

可视化原型:打开 [`docs/mockups/prototype.html`](docs/mockups/prototype.html) 看 UI 草案。

## 技术栈 / Tech Stack

- **语言 Language**: Swift 5.9+
- **UI**: SwiftUI + AppKit (`NSStatusItem`)
- **持久化 Persistence**: GRDB.swift
- **自动更新 Updater**: Sparkle 2.x
- **快捷键 Hotkey**: Carbon `RegisterEventHotKey`
- **最低系统 Min OS**: macOS 13 (Ventura)
- **分发 Distribution**: GitHub Release(开源)+ Mac App Store(后续)

## 数据源 / Data Sources

| Source | Markets | 鉴权 Auth | 默认启用 Default |
|---|---|---|---|
| 腾讯财经 / Tencent | A / HK / US | None | ✓ |
| 东方财富 / EastMoney | A / HK / US | None | ✓ |
| Yahoo Finance | A / HK / US | None | US ✓ |
| Finnhub | US | API Key | ☐ |

每市场的优先级和启用状态可在 **设置 → 数据源** 中调整。失败 30 秒冷却,自动按优先级 fallback。

## 隐私 / Privacy

PanBar **不收集、不上报、不存储任何个人数据**。所有持仓、自选、设置都只在本地 SQLite。
详见 [PRIVACY.md](PRIVACY.md)。

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

- [GRDB.swift](https://github.com/groue/GRDB.swift) — 类型安全的 SQLite 封装
- [Sparkle](https://sparkle-project.org/) — macOS 自动更新框架
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — 项目文件生成器
