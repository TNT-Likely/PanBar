# 发布流程 Release Guide

> PanBar 走开源 + 公证签名分发路线。本文档覆盖从打 tag 到用户能装上为止的全部步骤。

---

## 0. 一次性准备

### 0.1 Apple Developer 账号

- 加入 [Apple Developer Program](https://developer.apple.com/programs/) ($99/年)
- 在 Apple Developer 后台创建 **Developer ID Application** 证书并下载 `.p12`
- 记下 Team ID(在账号 → Membership)

### 0.2 App-specific Password(用于公证)

- 登录 <https://appleid.apple.com>
- Security → App-Specific Passwords → 生成一个,用途填 "PanBar Notarization"

### 0.3 本地凭据(Makefile 用)

创建 `.env`(已被 .gitignore):

```env
DEV_ID="Developer ID Application: Your Name (TEAMID12345)"
NOTARY_KEYCHAIN_PROFILE=panbar-notary
```

把 app-specific 密码存入 Keychain profile,避免明文:

```bash
xcrun notarytool store-credentials panbar-notary \
  --apple-id "you@example.com" \
  --team-id "TEAMID12345" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

### 0.4 Sparkle EdDSA 签名密钥

```bash
# 1) 下载 Sparkle 工具包(release 页里 Sparkle-2.x.tar.xz)
mkdir -p build/sparkle-tools && cd build/sparkle-tools
curl -L https://github.com/sparkle-project/Sparkle/releases/download/2.6.0/Sparkle-2.6.0.tar.xz | tar xJ
cd ../..

# 2) 生成 EdDSA 密钥对(只做一次,妥善保管私钥)
build/sparkle-tools/bin/generate_keys

# 3) 输出的 Public key 填入 project.yml 的 SUPublicEDKey
# 4) 私钥保存在 Keychain 名为 "Sparkle Account",签发时自动用到
```

### 0.5 GitHub Actions Secrets

打 Tag 自动发布前,在 GitHub 仓库 Settings → Secrets and variables → Actions 添加:

| Secret | 值 |
|---|---|
| `MAC_DEVELOPER_ID_P12_BASE64` | `base64 -i cert.p12` 的输出 |
| `MAC_DEVELOPER_ID_P12_PASSWORD` | p12 的密码 |
| `MAC_KEYCHAIN_PASSWORD` | 临时 keychain 密码(可随便填,只在 runner 里用) |
| `APPLE_ID` | 苹果账号邮箱 |
| `APPLE_APP_SPECIFIC_PASSWORD` | 0.2 生成的 app-specific 密码 |
| `APPLE_TEAM_ID` | 10 位 Team ID |

### 0.6 GitHub Pages(放 appcast.xml)

- 仓库 Settings → Pages → Source: `main` branch / `/docs` 目录
- 把生成的 `appcast.xml` 放到 `docs/` 下
- 访问 `https://tnt-likely.github.io/PanBar/appcast.xml` 验证可达

---

## 1. 本地发布(逐步操作)

```bash
# 1) 更新版本号(MARKETING_VERSION 在 Makefile 里通过 VERSION 传入)
VERSION=0.2.0

# 2) Release 构建
make release-build VERSION=$VERSION

# 3) 签名
make sign

# 4) 公证 + staple
make notarize VERSION=$VERSION

# 5) 打 DMG
make dmg VERSION=$VERSION

# 6) 生成 Sparkle 的 appcast 条目
build/sparkle-tools/bin/generate_appcast build/
# → 把生成的 build/appcast.xml 拷到 docs/ 提交 push

# 7) 创建 tag 与 GitHub Release
git tag $VERSION
git push origin $VERSION
gh release create $VERSION \
  --title "PanBar $VERSION" \
  --generate-notes \
  build/PanBar-$VERSION.dmg \
  build/PanBar-$VERSION.zip
```

## 2. 自动发布(推荐)

把代码 push 到 `main`,然后:

```bash
git tag 0.2.0
git push origin 0.2.0
```

GitHub Actions `.github/workflows/release.yml` 会自动:
1. 构建 Release
2. 用 secrets 里的证书签名
3. 公证 + staple
4. 打 DMG + ZIP
5. 创建 GitHub Release 并上传产物

随后手动运行 `generate_appcast` 更新 `docs/appcast.xml` 推送,Sparkle 即可生效。

---

## 3. 用户安装路径

- DMG:用户双击挂载 → 拖 PanBar.app 到 Applications
- 第一次启动 macOS 可能提示"无法打开",右键 → 打开 → 信任(只需一次)
- 公证后通常没这一步

---

## 4. 常见问题

### codesign 报 "no identity found"

Developer ID 证书没装上,或 `DEV_ID` 串写错。用 `security find-identity -p codesigning -v` 看实际证书名。

### 公证一直 In Progress

`xcrun notarytool log <submission-id> --keychain-profile panbar-notary` 查看具体错误,常见是 entitlements 不匹配或漏签了内嵌的 framework。

### Sparkle 提示 "Code-signing failed"

EdDSA 公钥(Info.plist 中 `SUPublicEDKey`)和签发用的私钥不匹配。检查 Keychain 中 "Sparkle Account" 是否对应。

### App Store 上架版本要做什么不同?

- 移除 Sparkle 依赖(走 App Store 自更新)
- `SUFeedURL` / `SUPublicEDKey` 删掉
- 走 `xcodebuild ... archive` 后用 `xcrun altool` 或 Xcode UI 上传

详细的 App Store 上架步骤见 `docs/APPSTORE.md`。
