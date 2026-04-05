# Clawbar notarized release process

Clawbar 的正式 macOS 发布现在走单独的 tag 驱动流水线，而不是 `main` 分支上的常规构建。

目标：

- PR / `main` 只负责 `swift build` / `swift test`
- `v*` tag 触发正式发布
- 正式发布产物是经过 `Developer ID Application` 签名、Apple notarization、stapling 和本地校验的 `.dmg`

## GitHub Actions 入口

正式发布 workflow:

- `.github/workflows/release-app.yml`

常规 CI workflow:

- `.github/workflows/swift.yml`

## 必须准备的 GitHub Secrets

以下 secrets 是正式发布必需项：

- `APPLE_DEVELOPER_ID_CERT_BASE64`
  `Developer ID Application` 证书导出的 `.p12` 文件内容，先做 base64 编码再写入 GitHub Secrets
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
  `.p12` 导出时设置的密码
- `APPLE_TEAM_ID`
  Apple Developer Team ID，用于校验导入到 runner 的签名身份是否正确
- `APPLE_NOTARY_KEY_ID`
  App Store Connect API key 的 Key ID
- `APPLE_NOTARY_ISSUER_ID`
  App Store Connect API key 的 Issuer ID
- `APPLE_NOTARY_API_KEY_BASE64`
  `.p8` 私钥文件内容，先做 base64 编码再写入 GitHub Secrets

## 一次性手动准备

1. 加入 Apple Developer Program。
2. 在本机钥匙串中创建或下载 `Developer ID Application` 证书。
3. 将证书导出成 `.p12` 并记住导出密码。
4. 在 App Store Connect 中创建一个 API Key，保存 `Key ID`、`Issuer ID` 和 `.p8` 私钥文件。
5. 将 `.p12` 和 `.p8` 分别转成 base64，写入上面的 GitHub Secrets。

示例：

```bash
base64 -i developer-id-application.p12 | pbcopy
base64 -i AuthKey_ABCD123456.p8 | pbcopy
```

## 本地建议验证

在把 secrets 放进 GitHub 之前，建议先在本机验证一次签名与公证链路：

```bash
export SIGNING_IDENTITY="Developer ID Application: Example Name (TEAMID1234)"
export APPLE_NOTARY_KEY_ID="..."
export APPLE_NOTARY_ISSUER_ID="..."
export APPLE_NOTARY_API_KEY_PATH="/absolute/path/to/AuthKey_ABCD123456.p8"

./Scripts/sign_and_notarize.sh
```

验证点：

- `dist/Clawbar.app` 已签名
- `dist/Clawbar-<version>.dmg` 已生成
- `notarytool submit --wait` 成功
- `stapler validate` 对 `.app` 和 `.dmg` 都通过
- Finder 能挂载 DMG，拖出 app 后首次启动不会出现未签名或 damaged 提示

## 每次正式发布的动作

1. 确认要发布的版本号，例如 `0.1.0`。
2. 创建并 push tag：

```bash
git tag v0.1.0
git push origin v0.1.0
```

3. 等待 `.github/workflows/release-app.yml` 完成。
4. 从 GitHub Release 下载生成的 DMG 并手动验证：

```bash
spctl --assess --type open -vvv Clawbar-0.1.0.dmg
codesign --verify --deep --strict --verbose=2 /Applications/Clawbar.app
xcrun stapler validate /Applications/Clawbar.app
```

## 脚本职责

`Scripts/package_app.sh`

- 构建通用或单架构 app
- 复制二进制与 Swift runtime
- 写入 `Info.plist` 和 `build-info.txt`
- 支持显式签名
- 支持输出 `.app` / `.zip` / `.dmg`

`Scripts/sign_and_notarize.sh`

- 调用 `package_app.sh` 生成正式签名的 app / dmg
- 使用 `notarytool submit --wait` 提交 DMG
- 对 `.app` 和 `.dmg` 执行 stapling
- 运行 `codesign`、`spctl`、`stapler validate` 做发布前校验

## 说明

- 正式 release 默认产物是 DMG，不再从 `main` 自动生成 GitHub Release zip。
- `Scripts/package_app.sh` 仍保留 zip 输出能力，主要用于本地调试或兼容性场景。
- 如果后续 notarization 日志显示需要额外 entitlements，再单独补 release-only entitlements，不要先猜。
