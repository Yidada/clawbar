# Clawbar notarized release process

Clawbar 的正式 macOS 发布现在采用版本文件和 changelog 驱动的 tag 流水线：

- `version.env` 是 release 版本元数据的唯一来源
- `CHANGELOG.md` 是 GitHub release notes 的唯一来源
- `v*` tag 必须与 `version.env` 中的 `MARKETING_VERSION` 一致
- 正式发布产物是经过 `Developer ID Application` 签名、Apple notarization、stapling 和本地校验的 `.dmg`
- `main-build` 继续作为持续打包的 prerelease 通道

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

1. 更新 `version.env` 中的 `MARKETING_VERSION`，并在需要时同步 `BUILD_NUMBER`。
2. 在 `CHANGELOG.md` 顶部维护对应版本 section，并把 `Unreleased` 改成正式发布日期。
3. 本地执行 preflight：

```bash
bash Scripts/validate_release_metadata.sh
bash Scripts/validate_changelog.sh "$(source version.env && echo "$MARKETING_VERSION")"
bash Scripts/extract_release_notes.sh "$(source version.env && echo "$MARKETING_VERSION")"
```

4. 创建并 push 对应 tag：

```bash
git tag v0.1.0
git push origin v0.1.0
```

5. 等待 `.github/workflows/release-app.yml` 完成。
6. 从 GitHub Release 下载生成的 `Clawbar-<version>.dmg` 并手动验证：

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

`Scripts/validate_release_metadata.sh`

- 校验 `version.env` 存在且包含合法的 `MARKETING_VERSION` / `BUILD_NUMBER`
- 在传入 tag 时校验 tag 与 `version.env` 一致

`Scripts/validate_changelog.sh`

- 校验顶层 changelog section 对应目标版本
- 阻止仍标记为 `Unreleased` 的版本直接发布

`Scripts/extract_release_notes.sh`

- 从 `CHANGELOG.md` 中提取目标版本的正文，作为 GitHub Release notes

`Scripts/check-release-assets.sh`

- 校验本地 `dist/Clawbar-<version>.dmg` 是否存在，便于 release 后做简单资产检查

## 说明

- 正式 release 默认产物是 DMG，不再发布 zip 作为公开安装包。
- `Scripts/package_app.sh` 仍保留 zip 输出能力，主要用于本地调试或兼容性场景。
- GitHub Release notes 不再写死为一句通用描述，而是直接从 `CHANGELOG.md` 提取。
- Homebrew Cask 还未接入；当前唯一公开分发渠道仍然是 GitHub Releases DMG。
- 如果后续 notarization 日志显示需要额外 entitlements，再单独补 release-only entitlements，不要先猜。
