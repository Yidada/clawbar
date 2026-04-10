# clawbar

[English](README.md)

Clawbar 是一个 macOS 14+ 菜单栏应用，用于本地安装、配置和操作 OpenClaw。它把常用运维入口集中到一个菜单栏应用里：安装或卸载 OpenClaw，管理 Gateway 和 Channels，准备内置 Ollama CLI/runtime，把 OpenClaw 固定到 `ollama/gemma4`，查看当前状态，并从菜单栏直接拉起 OpenClaw TUI。

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

- macOS 14+
- Swift tools 6.2 或更新版本
- 带 Swift 6.2 toolchain 的 Xcode，或独立 Swift 6.2+

`Package.swift` 当前声明为 `// swift-tools-version: 6.2`。如果本机只有 Swift 6.1.x，`swift build`、`swift run` 和 `swift test` 都会失败。

## Clawbar 管理内容

- OpenClaw 的安装与卸载，并在独立窗口中展示执行日志和状态反馈
- 本地 Gateway token 准备，以及 Gateway 后台服务管理
- 准备内置 Ollama CLI/runtime，自动下载 `gemma4`，并把 OpenClaw 固定绑定到 `ollama/gemma4`
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

本地无签名打包使用 `Scripts/package_app.sh`。默认产物是 zip；如果需要不同格式，可设置 `OUTPUT_FORMAT=app`、`dmg` 或 `both`。打包流程现在会下载固定版本的 Ollama release asset，把 CLI/runtime 嵌入到 `Contents/Resources/OllamaRuntime/`，并把 Ollama 版本写入 `build-info.txt`。

```bash
OUTPUT_FORMAT=dmg ./Scripts/package_app.sh
```

首次启动时，Clawbar 会启动内置 Ollama runtime，把 `gemma4` 下载到 `~/Library/Application Support/Clawbar/Ollama/models`，并恢复 OpenClaw 的默认模型到 `ollama/gemma4`。如果打包内置 runtime 缺失，Ollama 页面现在也提供应用内安装入口，会把官方 CLI/runtime 下载到 `~/Library/Application Support/Clawbar/Ollama/runtime`。这个版本不再暴露其他 Provider、远端 Ollama 地址或自定义模型选择。

如果要在本机验证签名与 notarization，先设置 `SIGNING_IDENTITY` 和所需的 notary 环境变量，再执行：

```bash
./Scripts/sign_and_notarize.sh
```

如果要把本地签名配置保存在项目里、但又不提交到 Git，可以先生成被忽略的 `.local/signing/` 目录：

```bash
python3 Scripts/prepare_signing_assets.py \
  --source-dir /absolute/path/to/signing-bundle \
  --output-dir .local/signing \
  --team-id YOUR_TEAM_ID \
  --signing-identity "Developer ID Application: Your Name (YOUR_TEAM_ID)" \
  --notary-key-id YOUR_KEY_ID \
  --notary-issuer-id YOUR_ISSUER_ID
```

之后先执行 `source .local/signing/local-notary.env`，再运行 `./Scripts/sign_and_notarize.sh`。
生成出来的本地 env 会把签名明确绑定到 `login.keychain-db`，避免本机残留的临时 signing keychain 干扰 `codesign`。

GitHub Actions 现在分成两条打包路径，复用同一套签名配置：

- 合入 `main` 后：执行测试、签名、公证，把 DMG 作为 workflow artifact 上传，并更新 `main-build` GitHub 预发布
- 推送 `v*` tag 后：执行正式 release 流程，并把 DMG 发布到 GitHub Releases

这两条 workflow 都从 GitHub Environment `release-signing` 读取 secrets，并且统一只对外产出 `.dmg`。

## 文档

- [docs/README.md](docs/README.md)：文档索引和维护约定
- [Tests/Harness/README.md](Tests/Harness/README.md)：本地控制与测试 harness 说明
- [docs/2026-04-05-notarized-release-process.md](docs/2026-04-05-notarized-release-process.md)：release 流水线和 GitHub secrets 要求
- [docs/2026-04-06-local-signing-guide.md](docs/2026-04-06-local-signing-guide.md)：本地证书准备、签名和 notarization 细节
- [docs/2026-04-07-main-branch-packaging-setup.md](docs/2026-04-07-main-branch-packaging-setup.md)：项目内本地签名配置目录与 GitHub Environment 配置方式

## OpenClaw 参考快照工作流

`References/openclaw` 是用于集成开发的 OpenClaw vendored snapshot。凡是依赖 OpenClaw 内部实现的改动，都应先读这里；除非任务本身就是同步上游快照，否则不要随意改它。

## 仓库说明

项目级 skills 位于 `.agents/skills/`，可通过 `python3 Scripts/project_skills.py` 管理。仓库内部协作约定请查看 `AGENTS.md`。
