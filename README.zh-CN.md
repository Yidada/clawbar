# clawbar

[English](README.md)

Clawbar 是一个 macOS 14+ 菜单栏应用，用于本地安装、配置和操作 OpenClaw。它把常用运维入口集中到一个菜单栏应用里：安装或卸载 OpenClaw，管理 Gateway、Provider、Channels，并从菜单栏直接拉起 OpenClaw TUI。

## 安装

### GitHub Releases

可从 [GitHub Releases](https://github.com/Yidada/clawbar/releases) 下载已完成 notarization 的 DMG 安装包。

### 从源码运行

在仓库根目录执行：

```bash
swift run Clawbar
```

## 环境要求

- macOS 14+
- Swift tools `6.2` 或更新版本
- 带 Swift 6.2 toolchain 的 Xcode，或独立 Swift 6.2+

当前 `Package.swift` 声明为 `// swift-tools-version: 6.2`。如果本机只有 Swift 6.1.x，`swift build`、`swift run` 和 `swift test` 都会失败。

## 首次运行

- 启动 Clawbar 后，在菜单栏中找到应用图标。
- 如果尚未安装 OpenClaw，可直接从菜单中进入安装流程。
- Provider、Gateway 和 Channels 的管理都在管理窗口中完成。
- 需要本地调试或配对时，可直接从菜单栏拉起 OpenClaw TUI。

## Clawbar 管理内容

- OpenClaw 的安装与卸载，并在独立窗口中展示执行日志和状态反馈。
- 本地 Gateway token 准备，以及 Gateway 后台服务管理。
- 通过 `openclaw` CLI 管理 Provider 配置、默认模型和认证状态。
- 支持飞书接入配置和微信接入流程的 Channels 管理。
- 菜单栏持续展示安装状态、可执行文件路径和最近状态摘要。

## 开发

开发主入口是统一 harness：`Tests/Harness/clawbarctl.py`。

```bash
swift build
python3 Tests/Harness/clawbarctl.py app dev-loop
python3 Tests/Harness/clawbarctl.py test unit --coverage-gate
python3 Tests/Harness/clawbarctl.py test smoke
python3 Tests/Harness/clawbarctl.py test integration --suite all
python3 Tests/Harness/clawbarctl.py test all
```

仓库根目录下的 `Scripts/*.sh` 仍然保留为兼容 wrapper，但新的自动化和文档应优先使用上面的 harness 命令。

更多 harness 说明见 [Tests/Harness/README.md](Tests/Harness/README.md)。

## 发布

Clawbar 采用 tag 驱动的 notarized DMG 发布流程。推送 `v*` tag 后，GitHub Actions 会执行测试、签名、公证、stapling，并将 DMG 发布到 GitHub Releases。

发布前置条件和完整步骤见 [docs/2026-04-05-notarized-release-process.md](docs/2026-04-05-notarized-release-process.md)。

## 文档

- [docs/README.md](docs/README.md) 汇总项目文档
- [Tests/Harness/README.md](Tests/Harness/README.md) 说明本地控制与测试 harness
- [docs/2026-04-05-notarized-release-process.md](docs/2026-04-05-notarized-release-process.md) 记录签名、公证和 DMG 发布流程

## 仓库说明

`References/openclaw` 是用于集成开发的 OpenClaw 本地参考快照。项目级 skills 放在 `.agents/skills/`，可通过 `python3 Scripts/project_skills.py` 管理。

仓库内部协作约定请查看 `AGENTS.md`。
