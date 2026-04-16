# clawbar

[English](README.md)

Clawbar 是一个 macOS 13+ 菜单栏应用，用于本地安装、配置和操作 OpenClaw。它把常用运维入口集中到一个菜单栏应用里：安装或卸载 OpenClaw，管理 Gateway、Provider、Channels，查看当前状态，并从菜单栏直接拉起 OpenClaw TUI。

## 安装

### GitHub Releases

可从 [GitHub Releases](https://github.com/Yidada/clawbar/releases) 下载已完成 notarization 的 DMG 安装包。

### 从源码运行

在仓库根目录执行：

```bash
swift build
swift run Clawbar
```

## 环境要求

- macOS 13+
- Swift tools 6.2 或更新版本
- 带 Swift 6.2 toolchain 的 Xcode，或独立 Swift 6.2+

`Package.swift` 当前声明为 `// swift-tools-version: 6.2`。如果本机只有 Swift 6.1.x，`swift build`、`swift run` 和 `swift test` 都会失败。

## Clawbar 管理内容

- OpenClaw 的安装与卸载，并在独立窗口中展示执行日志和状态反馈；卸载时保留 `~/.openclaw`
- 本地 Gateway token 准备，以及 Gateway 后台服务管理
- 通过 `openclaw` CLI 管理 Provider 配置、默认模型和认证状态
- 支持飞书接入配置和微信接入流程的 Channels 管理
- 菜单栏持续展示安装状态、可执行文件路径和最近状态摘要

## 仓库结构

- `Sources/ClawbarKit/`：共享生命周期、菜单状态和其他可测试逻辑
- `Sources/Clawbar/`：应用入口、SwiftUI/AppKit 集成和 OpenClaw 管理流程
- `Tests/ClawbarTests/`：共享逻辑与分组集成流程的 XCTest 覆盖
- `Tests/Harness/`：dev loop、smoke、integration、diagnostics 的统一 harness 入口
- `docs/`：当前仍然有效的流程说明和发布文档
- `.agents/skills/`：项目自带 skills
- `References/openclaw/`：用于集成开发的 OpenClaw 上游快照
- `Artifacts/`：harness 运行产物、诊断包、截图等输出

## 常用工作流

### 运行并检查应用

```bash
swift run Clawbar
python3 Tests/Harness/clawbarctl.py app start --mode menu-bar --restart
python3 Tests/Harness/clawbarctl.py app status
python3 Tests/Harness/clawbarctl.py app stop
```

### 开发与验证

```bash
python3 Tests/Harness/clawbarctl.py app dev-loop
python3 Tests/Harness/clawbarctl.py test unit --coverage-gate
python3 Tests/Harness/clawbarctl.py test smoke
python3 Tests/Harness/clawbarctl.py test integration --suite all
python3 Tests/Harness/clawbarctl.py test integration --suite provider
python3 Tests/Harness/clawbarctl.py test all
python3 Tests/Harness/clawbarctl.py logs collect
```

Harness 会把每次运行的摘要写到 `Artifacts/Harness/Runs/`，并把当前后台 app 进程状态写到 `Artifacts/Harness/State/app-state.json`。

根目录下的 `Scripts/dev.sh`、`Scripts/check_coverage.sh`、`Scripts/smoke_test.sh`、`Scripts/test.sh` 仍保留为兼容 wrapper，但新的文档和自动化应优先使用 `Tests/Harness/clawbarctl.py`。

## 打包与发布

本地无签名打包使用 `Scripts/package_app.sh`。默认产物是 zip；如果需要不同格式，可设置 `OUTPUT_FORMAT=app`、`dmg` 或 `both`。

```bash
OUTPUT_FORMAT=dmg ./Scripts/package_app.sh
```

如果要在本机验证签名与 notarization，先设置 `SIGNING_IDENTITY` 和所需的 notary 环境变量，再执行：

```bash
./Scripts/sign_and_notarize.sh
```

正式发布使用 GitHub Actions 的 tag 驱动流程。推送 `v*` tag 后，流水线会执行测试、签名、公证、stapling，并把 DMG 发布到 GitHub Releases。

如果你是在 GitLab 上发布，仓库也提供了一份 `.gitlab-ci.yml` 模板：默认分支每次合入后自动签名、notarization、上传到 GitLab Package Registry，并在 GitLab Release 页面挂下载链接。说明见 [docs/2026-04-07-gitlab-main-branch-release.md](docs/2026-04-07-gitlab-main-branch-release.md)。

如果你现在跑的是 ByteDance Codebase CI，而且变量配置在 `Codebase CI -> Variables`，则应该使用 [.codebase/pipelines/main-notarized-release.yml](.codebase/pipelines/main-notarized-release.yml)。对应说明见 [docs/2026-04-07-codebase-ci-main-release.md](docs/2026-04-07-codebase-ci-main-release.md)。

## 文档

- [docs/README.md](docs/README.md)：文档索引和维护约定
- [Tests/Harness/README.md](Tests/Harness/README.md)：本地控制与测试 harness 说明
- [docs/2026-04-05-notarized-release-process.md](docs/2026-04-05-notarized-release-process.md)：release 流水线和 GitHub secrets 要求
- [docs/2026-04-06-local-signing-guide.md](docs/2026-04-06-local-signing-guide.md)：本地证书准备、签名和 notarization 细节
- [docs/2026-04-07-gitlab-main-branch-release.md](docs/2026-04-07-gitlab-main-branch-release.md)：GitLab 默认分支自动打包、签名和挂载下载链接的流水线
- [docs/2026-04-07-codebase-ci-main-release.md](docs/2026-04-07-codebase-ci-main-release.md)：适配 Codebase CI Variables 的 main 合入自动签名发布流水线

## OpenClaw 参考快照工作流

`References/openclaw` 是用于集成开发的 OpenClaw vendored snapshot。凡是依赖 OpenClaw 内部实现的改动，都应先读这里；除非任务本身就是同步上游快照，否则不要随意改它。

## 仓库说明

项目级 skills 位于 `.agents/skills/`，可通过 `python3 Scripts/project_skills.py` 管理。仓库内部协作约定请查看 `AGENTS.md`。
