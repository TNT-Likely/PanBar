# Privacy Policy / 隐私政策

**Last updated:** 2026-05-21
**最近更新:** 2026-05-21

---

## English

### TL;DR

PanBar does not collect, store, transmit, or share any personal data. Everything stays on your Mac.

### What data does PanBar process?

| Data | Where it lives | Sent to third parties? |
|---|---|---|
| Holdings, watchlist, alerts | Local SQLite at `~/Library/Application Support/PanBar/panbar.sqlite` | No |
| Settings (theme, base currency, API keys) | Local SQLite | No |
| Stock quote requests | HTTPS calls to the data sources **you have enabled** (Tencent / EastMoney / Yahoo / Finnhub) | Yes — each provider sees only your stock symbol queries (no identity) |
| Crash logs / analytics | None | None |

### Third-party data sources

When you enable a data source, PanBar makes HTTPS requests to that provider's quote endpoint. PanBar **does not** include any user identifier in these requests — providers only see the stock codes you're tracking.

- **Tencent / EastMoney** — public web endpoints, no authentication
- **Yahoo Finance** — public chart API, no authentication
- **Finnhub** — requires your API key, used for authentication only

You can disable any provider at **Settings → Data Sources**.

### Analytics, telemetry, crash reporting

**None.** PanBar contains no analytics, telemetry, ads, or crash reporting SDK. It does not "phone home" to any first-party server.

### Auto-update

PanBar checks for new releases via [Sparkle](https://sparkle-project.org/) against `https://tnt-likely.github.io/PanBar/appcast.xml`. The update request reveals only your IP address and User-Agent string (standard HTTPS metadata). No personal data is sent.

### How to wipe local data

Quit PanBar, then:

```
rm -rf ~/Library/Application\ Support/PanBar
```

### Contact

Open an issue at <https://github.com/TNT-Likely/PanBar/issues>.

---

## 简体中文

### 一句话

PanBar 不收集、不存储、不上报任何个人数据。所有数据都只保存在你的 Mac 上。

### PanBar 会处理哪些数据?

| 数据 | 存放位置 | 是否发给第三方 |
|---|---|---|
| 持仓、自选股、预警 | 本地 SQLite:`~/Library/Application Support/PanBar/panbar.sqlite` | 否 |
| 设置(主题、本位币、API Key) | 本地 SQLite | 否 |
| 行情请求 | 走你**在设置里启用**的数据源(腾讯 / 东方财富 / Yahoo / Finnhub)的 HTTPS 接口 | 是 — 仅股票代码,无任何身份信息 |
| 崩溃日志 / 分析数据 | 无 | 无 |

### 第三方数据源

启用某个数据源后,PanBar 会对其行情接口发起 HTTPS 请求。**请求中不包含任何用户身份信息**,数据源只会看到你查询的股票代码。

- **腾讯 / 东方财富** — 公开 web 接口,无需鉴权
- **Yahoo Finance** — 公开 chart API,无需鉴权
- **Finnhub** — 需要你提供的 API Key,仅用于鉴权

你可以在 **设置 → 数据源** 中关闭任一 provider。

### 分析、埋点、崩溃上报

**完全没有。** PanBar 内不包含任何分析、埋点、广告或崩溃上报 SDK,不会向任何第一方服务器"打电话"。

### 自动更新

PanBar 通过 [Sparkle](https://sparkle-project.org/) 检查 `https://tnt-likely.github.io/PanBar/appcast.xml` 上的新版本。请求只会暴露你的 IP 与 User-Agent(任何 HTTPS 请求都会带),不会发送任何个人数据。

### 如何清除本地数据

退出 PanBar 后执行:

```
rm -rf ~/Library/Application\ Support/PanBar
```

### 联系方式

到 <https://github.com/TNT-Likely/PanBar/issues> 提 issue。
