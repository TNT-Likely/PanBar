# App Store 上架准备

> 上架 App Store 是可选路线。如果只走 GitHub Release + Sparkle 分发,可以跳过本文。

---

## 1. 与 GitHub 版本的差异

App Store 版本必须移除以下东西:

| 项 | 原因 | 操作 |
|---|---|---|
| Sparkle 自动更新 | App Store 不允许第三方更新机制 | 用 `#if APPSTORE` 条件编译屏蔽 `Updater` 调用 |
| `SUFeedURL` / `SUPublicEDKey` | 不需要 | 从 Info.plist 删除 |
| 公网股价接口(腾讯/东财) | 这些接口未授权商用,有合规风险 | 默认全关,要求用户填 Finnhub Key 才能拉行情 |

建议在 project.yml 增加一个 target `PanBar-AppStore`,与主 target 共享代码,仅 build setting 不同。

---

## 2. App Store Connect 元数据

### 2.1 Bundle / 版本

- Bundle ID: `app.panbar.PanBar`(已占用就改 `app.panbar.PanBarMac`)
- SKU: `PANBAR-001`
- Primary language: 简体中文 / 双语描述

### 2.2 文案模板

**App 名称**:`PanBar — 菜单栏盯盘工具`

**副标题**(30 字以内):`A 股 / 港股 / 美股实时滚动行情`

**描述**(简体中文):

```
PanBar 是一个常驻 macOS 菜单栏的轻量盯盘工具。把你关心的股票放进自选,
让最新价、涨跌幅、持仓盈亏在菜单栏不停地滚动 —— 不打开任何窗口,
也能掌握全局。

• 一栏滚动:菜单栏自定义滚动你最关心的几只股票
• 持仓盈亏:今日 / 累计盈亏自动按本位币(¥ / $ / HK$)汇总
• 三市覆盖:A 股、港股、美股
• 全市场指数:沪指、深成指、恒生、纳指、标普一站式
• 价格预警:涨跌触发系统通知,不打扰
• 数据自选:免费数据源 + 可填 Finnhub Key 解锁实时美股
• 完全本地:数据从不离开你的 Mac,无埋点 无广告
• 中英双语 · 深色模式 · 开机启动
```

**关键词**:`股票,菜单栏,行情,盯盘,自选股,持仓,A股,港股,美股`

**支持网址**:`https://github.com/TNT-Likely/PanBar`
**营销网址**:同上(或专门做一个落地页)
**隐私政策网址**:`https://github.com/TNT-Likely/PanBar/blob/main/PRIVACY.md`

### 2.3 截图清单(需要准备)

| 尺寸 | 内容建议 |
|---|---|
| 1280×800 | 菜单栏 ticker + 桌面背景 |
| 1280×800 | Popover 展开 · Holdings 面板 |
| 1280×800 | Settings → Data Sources 面板 |
| 1280×800 | 价格预警通知 |
| 1280×800 | 大盘指数 Tab |

工具:`Xcode → Window → Devices and Simulators`,或直接 ⌘+⇧+4 截图后裁剪。

### 2.4 类别

- 主类别:`Finance`
- 次类别:`Productivity`

### 2.5 评级

- Age Rating:4+(无敏感内容)

---

## 3. 隐私清单(已包含)

`PanBar/Resources/PrivacyInfo.xcprivacy` 已经填好,声明:
- 不追踪 (NSPrivacyTracking = false)
- 不收集任何 data type
- 仅访问 UserDefaults(CA92.1)、FileTimestamp(C617.1)等系统 API

App Store 审核会读这个文件。

---

## 4. 沙盒与权限审核要点

PanBar 的 entitlements:
- ✅ `com.apple.security.app-sandbox` — 必需
- ✅ `com.apple.security.network.client` — 拉行情
- ✅ `com.apple.security.files.user-selected.read-write` — CSV 导入/导出

审核员会问:
> 为什么需要网络?

→ 在审核备注里写:`Used to fetch stock quotes from user-configured public market data endpoints. No analytics or third-party tracking.`

> 为什么需要文件读写?

→ `Only for user-initiated CSV import/export of their own portfolio data.`

---

## 5. 上传步骤

```bash
# 1) Release 构建(走 App Store 配置)
xcodebuild -project PanBar.xcodeproj -scheme PanBar-AppStore \
  -configuration Release \
  -archivePath build/PanBar-AppStore.xcarchive \
  archive

# 2) 导出 App Store 签名版
xcodebuild -exportArchive \
  -archivePath build/PanBar-AppStore.xcarchive \
  -exportOptionsPlist scripts/export-options-appstore.plist \
  -exportPath build/AppStore

# 3) 上传
xcrun altool --upload-app -f build/AppStore/PanBar.pkg \
  --type macos \
  --username "you@example.com" \
  --password "@keychain:AC_PASSWORD"

# 也可以在 Xcode → Organizer 里 Distribute App → App Store Connect
```

---

## 6. 审核时间

- 首次提交:1-3 个工作日
- 后续版本:通常 24 小时内
- 拒审常见原因:数据源使用未授权 API(把腾讯/东财关掉,要求用户填 key 即可)
