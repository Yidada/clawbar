# GitLab `main` 分支自动签名发布

这份说明对应仓库根目录的 `.gitlab-ci.yml`，目标是让代码合入默认分支后自动完成以下动作：

如果你的密钥不是配在 GitLab Runner Variables，而是配在 `Codebase CI -> Variables`，请改用 `docs/2026-04-07-codebase-ci-main-release.md` 和 `.codebase/pipelines/main-notarized-release.yml`。

1. 运行测试
2. 构建 `.dmg`
3. 使用 `Developer ID Application` 证书签名
4. 提交 Apple notarization，并完成 stapling / 本地校验
5. 把 DMG 上传到 GitLab Package Registry
6. 在 GitLab Release 页面挂一个可下载的资产链接

## 触发策略

- Merge Request pipeline：只跑 `swift test`
- 默认分支 push pipeline：跑测试，然后自动打包、签名、公证、上传

如果你只希望“通过 merge 合入 `main`”才触发，而不允许直接 push 触发，应该在 GitLab 的 branch protection / branch rules 里把默认分支保护起来，只允许通过 Merge Request 合入。

## Runner 要求

这条流水线必须跑在 macOS runner 上，推荐使用 shell executor，并给 runner 打一个固定 tag：

```text
macos-signing
```

`.gitlab-ci.yml` 当前默认写的是这个 tag。如果你的 runner tag 不一样，改掉 `default.tags` 即可。

Runner 还需要满足：

- 已安装 Xcode 26.2，或把 `DEVELOPER_DIR` 改成你机器上的 Xcode 路径
- 可执行 `swift`
- 可执行 `codesign`
- 可执行 `xcrun notarytool`
- 可执行 `xcrun stapler`
- 能访问 Apple notarization 服务和 GitLab API

## 必填 GitLab CI/CD Variables

在 `Settings > CI/CD > Variables` 中新增以下变量，并建议设为 `Masked` + `Protected`：

- `APPLE_DEVELOPER_ID_CERT_BASE64`
  `Developer ID Application` 证书导出的 `.p12` 文件内容，先做 base64
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
  `.p12` 导出密码
- `APPLE_TEAM_ID`
  Apple Developer Team ID，用于校验导入到临时 keychain 的 identity
- `APPLE_NOTARY_KEY_ID`
  App Store Connect API key 的 Key ID
- `APPLE_NOTARY_ISSUER_ID`
  App Store Connect API key 的 Issuer ID
- `APPLE_NOTARY_API_KEY_BASE64`
  `.p8` 私钥内容，先做 base64

## 流水线结构

### `test`

- 所有 MR 和默认分支都会跑
- 执行 `swift test -v`

### `prepare_main_release`

- 只在默认分支 push 上执行
- 生成这一轮发布需要的元数据：
  - `RELEASE_TAG=main-<pipeline_iid>`
  - `DMG_BASENAME=Clawbar-<utc-date>-main-<pipeline_iid>`
  - GitLab Package Registry 上传地址
  - GitLab Release 下载地址

### `package_main_release`

- 导入 base64 `.p12` 到临时 keychain
- 从证书中解析 `Developer ID Application` identity
- 校验 identity 里是否包含 `APPLE_TEAM_ID`
- 写出 `.p8` notary key
- 调用现有的 `./Scripts/sign_and_notarize.sh`
- 把生成的 DMG 上传到 GitLab Generic Package Registry

这个 job 复用了现有脚本，不在 CI 里复制打包逻辑：

- `Scripts/package_app.sh`
- `Scripts/sign_and_notarize.sh`

### `publish_main_release`

- 使用 GitLab Releases API 自动创建或更新一个 release
- release tag 直接指向本次合入默认分支的 commit
- 给 release 增加一个 asset link，目标指向刚刚上传的 Package Registry DMG

最终用户可以从两个地方拿到文件：

- 当前 pipeline 的 job artifact
- GitLab Release 页面上的 DMG 下载链接

## 产物命名

默认命名规则：

- Release tag：`main-<pipeline_iid>`
- DMG：`Clawbar-<UTC日期>-main-<pipeline_iid>.dmg`

这样可以保证每次合入默认分支都有独立的版本，不会和前一轮签名产物互相覆盖。

## 为什么同时用 Package Registry 和 Release

不建议只依赖 job artifact，因为 artifact 更偏向流水线产物，保留策略通常会过期。

这里的设计是：

- Job artifact：给当前 pipeline 调试和快速回看
- Package Registry：给 GitLab 托管实际二进制文件
- Release asset link：给最终下载入口

## 首次接入建议顺序

1. 先在本机跑通 `./Scripts/sign_and_notarize.sh`
2. 在 GitLab 上准备好 macOS runner
3. 配置 6 个 Apple 相关变量
4. 保护默认分支，避免直接 push
5. 合并一个小改动到默认分支，观察 `package_main_release` 和 `publish_main_release`

## 可选调整

- 如果不想在每次默认分支合并都做 notarization，可以把 `package_main_release` 改成手动 job
- 如果需要给外部用户一个固定链接，可以在 release asset 的 `filepath` 维持固定命名，例如 `/binaries/Clawbar.dmg`
- 如果想保留 GitHub tag release 作为正式发行、GitLab `main` 产物只做内部分发，可以两套并存
