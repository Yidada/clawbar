# Clawbar 当前状态后的 notarization 与 GitHub 发布接入指引

这份文档从当前仓库和当前账号状态继续，不再重复证书申请、CSR 生成、证书导入这些已经完成的步骤。

本文默认你已经具备：

- 本机可用的 `Developer ID Application` 证书
- 本机可执行 `swift build`
- 本机可执行 `xcrun notarytool`
- 仓库里的已签名 DMG 能正常产出

当前已确认的签名身份：

```text
Developer ID Application: Benjamin Zhang (9247PC9936)
```

当前 Team ID：

```text
9247PC9936
```

## 目标

接下来只做三件事：

1. 在 Apple 后台状态恢复后创建 notarization 用的 App Store Connect Team API key
2. 用这套 key 在本机跑通 `sign_and_notarize.sh`
3. 把 `.p12` 和 `.p8` 接进 GitHub Actions 的 release workflow

## 当前仓库已经支持的发布链路

仓库里已经有正式发布 workflow：

- `.github/workflows/release-app.yml`

它已经支持以下能力，不需要再改脚本：

- 从 GitHub Secrets 读取 `.p12`
- 导入临时 keychain
- 校验 `Developer ID Application` identity 是否匹配 Team ID
- 从 GitHub Secrets 读取 `.p8`
- 调用 `Scripts/sign_and_notarize.sh`
- 生成、签名、notarize、staple、校验 `.dmg`
- 上传 GitHub Release

所以你明天真正需要补的不是 workflow 逻辑，而是 secrets。

## 明天拿到 key 之后需要准备的材料

等 App Store Connect 可以创建 Team API key 后，你要拿到这三项：

- `AuthKey_XXXXXX.p8`
- `Key ID`
- `Issuer ID`

另外，GitHub workflow 还需要你本地证书的 `.p12` 导出文件和它的导出密码。

最终需要的 GitHub secrets 一共是：

- `APPLE_DEVELOPER_ID_CERT_BASE64`
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_BASE64`

## 第一步：导出当前本地证书为 `.p12`

这一步是给 GitHub Actions 用的，不是给本地 `codesign` 用的。

在 Keychain Access 里：

1. 找到 `Developer ID Application: Benjamin Zhang (9247PC9936)`
2. 确认证书下方带私钥
3. 右键导出
4. 保存为 `clawbar-developer-id.p12`
5. 设置导出密码并记住

建议保存到一个清晰的位置，例如：

```text
~/Desktop/clawbar-developer-id.p12
```

## 第二步：把 `.p12` 和 `.p8` 转成 base64

拿到 `.p12` 和 `.p8` 后，执行：

```bash
base64 -i ~/Desktop/clawbar-developer-id.p12 > ~/Desktop/clawbar-developer-id.p12.base64.txt
base64 -i /absolute/path/to/AuthKey_XXXXXX.p8 > ~/Desktop/AuthKey_XXXXXX.p8.base64.txt
```

如果你更喜欢直接复制到剪贴板：

```bash
base64 -i ~/Desktop/clawbar-developer-id.p12 | pbcopy
base64 -i /absolute/path/to/AuthKey_XXXXXX.p8 | pbcopy
```

## 第三步：更新 GitHub Secrets

在 GitHub 仓库页面进入：

`Settings > Secrets and variables > Actions`

新增或更新以下 secrets：

### 证书相关

- `APPLE_DEVELOPER_ID_CERT_BASE64`
  填 `clawbar-developer-id.p12` 的 base64 内容
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
  填导出 `.p12` 时设置的密码
- `APPLE_TEAM_ID`
  填：

```text
9247PC9936
```

### notarization 相关

- `APPLE_NOTARY_KEY_ID`
  填 Team API key 的 `Key ID`
- `APPLE_NOTARY_ISSUER_ID`
  填 Team API key 的 `Issuer ID`
- `APPLE_NOTARY_API_KEY_BASE64`
  填 `AuthKey_XXXXXX.p8` 的 base64 内容

## 第四步：本地先验证一次完整 notarization

在把 secrets 交给 GitHub Actions 之前，建议先在本机验证一次。这样能把 Apple 后台问题和 CI 配置问题拆开。

在仓库根目录执行：

```bash
export SIGNING_IDENTITY="Developer ID Application: Benjamin Zhang (9247PC9936)"
export APPLE_NOTARY_KEY_ID="YOUR_KEY_ID"
export APPLE_NOTARY_ISSUER_ID="YOUR_ISSUER_ID"
export APPLE_NOTARY_API_KEY_PATH="/absolute/path/to/AuthKey_XXXXXX.p8"

./Scripts/sign_and_notarize.sh
```

如果你希望输出文件名带明确版本号，再加：

```bash
export APP_VERSION="0.1.0"
```

完整示例：

```bash
export SIGNING_IDENTITY="Developer ID Application: Benjamin Zhang (9247PC9936)"
export APP_VERSION="0.1.0"
export APPLE_NOTARY_KEY_ID="ABCD123456"
export APPLE_NOTARY_ISSUER_ID="11111111-2222-3333-4444-555555555555"
export APPLE_NOTARY_API_KEY_PATH="$HOME/Desktop/AuthKey_ABCD123456.p8"

./Scripts/sign_and_notarize.sh
```

## 第五步：本地验证通过后再交给 GitHub Actions

本地跑通后，再去看 GitHub release workflow。

当前 workflow 会自动读取：

- `APPLE_DEVELOPER_ID_CERT_BASE64`
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_BASE64`

它会自动：

1. 在 runner 上创建临时 keychain
2. 导入 `.p12`
3. 解析出 `Developer ID Application` identity
4. 检查 identity 是否包含 `(${APPLE_TEAM_ID})`
5. 写出 `.p8`
6. 执行 `./Scripts/sign_and_notarize.sh`

所以只要 secrets 对，workflow 不需要额外手改。

## 第六步：触发正式发布

Secrets 配好之后，正式发布动作用 tag 触发：

```bash
git tag v0.1.0
git push origin v0.1.0
```

然后到 GitHub Actions 看：

- `Release App`

成功后去 GitHub Releases 下载 DMG 再做一次人工验证：

```bash
spctl --assess --type open -vvv Clawbar-0.1.0.dmg
codesign --verify --deep --strict --verbose=2 /Applications/Clawbar.app
xcrun stapler validate /Applications/Clawbar.app
```

## 推荐的明日执行顺序

明天 Apple 后台恢复正常之后，按这个顺序做，最省时间：

1. 在 App Store Connect 创建 Team API key
2. 记下 `Key ID`、`Issuer ID`，下载 `.p8`
3. 从钥匙串导出当前 `Developer ID Application` 证书为 `.p12`
4. 把 `.p12` 和 `.p8` 各自转成 base64
5. 先在本机执行一次 `./Scripts/sign_and_notarize.sh`
6. 本地通过后，把 6 个 secrets 写进 GitHub
7. push 一个 `v*` tag，观察 `Release App` workflow

## 当前最可能遇到的阻塞

### 1. App Store Connect 仍然提示 `Membership Expired`

这不是脚本问题，而是 Apple 后台状态还没同步完成。只要这个状态还在，Team API key 创建就可能继续失败。

### 2. `API Keys cannot be created due to an invalid Program License Agreement`

这说明 Apple 后台仍然认为 Program License Agreement 未完成处理，即使你已经续费。优先重新检查：

- `developer.apple.com/account`
- `Membership details`
- `Agreements`

如果 24 小时后仍然不恢复，再联系 Apple Developer Support。

### 3. GitHub Actions 里 identity 校验失败

workflow 当前会检查导入后的 identity 是否包含：

```text
(9247PC9936)
```

如果 `.p12` 不是这张证书，workflow 会直接失败。

### 4. 本地能签名但 GitHub notarization 失败

优先检查：

- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_BASE64`

这三项任何一个不匹配，`notarytool submit` 都会失败。

## 这份文档之后不再覆盖的内容

如果你之后要回看已经完成的内容，例如：

- CSR 生成
- `Developer ID Application` 证书申请
- 证书导入钥匙串
- 本地首次签名验证

请直接看历史记录或更早版本的操作过程，不再把这些步骤继续堆回这份文档。
