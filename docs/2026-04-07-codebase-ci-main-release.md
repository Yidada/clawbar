# Codebase CI `main` 合入自动签名发布

这份说明对应 `.codebase/pipelines/main-notarized-release.yml`，适用于你把敏感信息配置在 **Codebase CI - Variables**，而不是 GitLab Runner Variables 的场景。

目标：

1. 仅在 MR 合入 `main` 时触发
2. 在 macOS 环境里构建 DMG
3. 使用 `Developer ID Application` 证书签名
4. 提交 Apple notarization 并完成 stapling / 校验
5. 上传到 GitLab Package Registry
6. 在 GitLab Release 页面挂一个可下载的 asset link

## 为什么要单独用 Codebase CI 配置

Codebase CI 的变量和 `.gitlab-ci.yml` 直接读取的 GitLab Runner Variables 不是一套系统。

如果你把 Apple 证书和 notary key 配在：

- `Codebase CI -> Variables`

那么应该使用：

- `.codebase/pipelines/main-notarized-release.yml`

而不是只依赖 `.gitlab-ci.yml`。

## 触发策略

当前配置使用：

- `trigger.change`
- `branches: [ main ]`
- `types: [ submit ]`

也就是只有 MR 真正合入 `main` 时才会执行，不会在普通 MR push 或直接 push 分支时重复跑。

## 需要的 Variables

除了前面已经准备好的 Apple 相关 6 个变量，这条流水线还额外需要：

- `GITLAB_RELEASE_TOKEN`

用途：

- 上传 DMG 到 GitLab Package Registry
- 调用 GitLab Releases API 创建或更新 release
- 给 release 增加下载链接

建议这个 token 至少具备对应仓库的 `api` 或 `write_api` 能力。

## 现有 7 个变量清单

- `APPLE_DEVELOPER_ID_CERT_BASE64`
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_BASE64`
- `GITLAB_RELEASE_TOKEN`

## 流水线行为

### 环境校验

第一步会检查：

- 7 个必需变量是否存在
- 当前 macOS 环境是否存在 `xcodebuild` / `swift`
- `swift --version` 是否至少为 6.2

如果环境低于 Swift 6.2，会直接失败并提示升级 runner。

### 打包和公证

流水线复用了仓库现有脚本：

- `Scripts/package_app.sh`
- `Scripts/sign_and_notarize.sh`

不会在 CI 里复制一套新的签名和 notarization 逻辑。

### 发布到 GitLab

发布步骤会：

1. 根据仓库远端推导 GitLab API 地址
2. 把 DMG 上传到 Generic Package Registry
3. 创建或更新一个 release
4. 给 release 追加一个名为 `Signed and notarized DMG` 的资产链接

## Release 命名

为了避免每次合入 `main` 互相覆盖，当前使用：

- Release tag：`main-<mr_id>-<short_sha>`
- DMG：`Clawbar-<UTC日期>-main-<mr_id>-<short_sha>.dmg`

## macOS 环境注意事项

Codebase CI 的公共 macOS 环境文档里写的是较老的 Xcode 版本。如果你的公共环境仍然只有旧版 Xcode，这个仓库会因为 `swift-tools-version: 6.2` 而构建失败。

因此上线前要确认至少满足其一：

- runner 已安装 Swift 6.2 / Xcode 26.2 级别工具链
- 或你有可控的自托管 macOS 环境

当前流水线会优先尝试：

- `/Applications/Xcode_26.2.app/Contents/Developer`
- `/Applications/Xcode.app/Contents/Developer`

## 与 `.gitlab-ci.yml` 的关系

- `.gitlab-ci.yml`
  适合标准 GitLab Runner 场景
- `.codebase/pipelines/main-notarized-release.yml`
  适合你现在这种把变量放进 Codebase CI 的场景

如果后续统一迁回标准 GitLab Runner，可以继续保留 `.gitlab-ci.yml`；如果内部只跑 Codebase CI，就以 `.codebase/pipelines/main-notarized-release.yml` 为主。
