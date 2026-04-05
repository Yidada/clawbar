# clawbar

Clawbar 是一个 macOS 菜单栏应用，用于本地安装、管理和操作 OpenClaw。

它已经不再是早期的 Hello World 示例，而是一个围绕 OpenClaw 本机运行体验构建的桌面运维入口：从安装、卸载，到 Gateway、Provider、Channels 和 TUI 启动，都在同一个菜单栏应用里完成。

## 当前能力

- 菜单栏常驻入口，显示 OpenClaw 安装状态、可执行文件路径和最近状态摘要。
- 安装 / 卸载 OpenClaw，并在独立窗口中展示执行日志、状态文本和后续处理结果。
- 安装完成后自动准备本地 Gateway token，并尝试安装 Gateway 后台服务。
- 管理窗口内置 3 个页签：
  - `Provider`：通过 `openclaw` CLI 读取并写回 Provider 配置、默认模型和认证状态。
  - `Gateway`：查看服务状态、PID、CLI 路径，并执行启动、重启、暂停、刷新。
  - `Channels`：维护飞书入口配置，并按官方流程安装 / 扫码接入微信能力。
- 支持的 Provider 类型：`OpenAI`、`Anthropic`、`OpenRouter`、`LiteLLM`、`Ollama`、`Custom`。
- 支持从菜单栏一键拉起 OpenClaw TUI，并自动带上本地 Gateway 凭证辅助调试或配对。

## 环境要求

- macOS 14+
- Swift tools `6.2` 或更新版本
- Xcode 中可用的 Swift 6.2 toolchain，或独立 Swift 6.2+

`Package.swift` 当前声明为 `// swift-tools-version: 6.2`。如果本机只有 Swift 6.1.x，`swift build` / `swift test` 会直接失败。

## 快速开始

在仓库根目录执行：

```bash
swift run Clawbar
```

首次运行后，应用会以菜单栏图标形式驻留。若尚未安装 OpenClaw，可直接从菜单中打开安装流程。

## 开发命令

构建：

```bash
swift build
```

运行测试：

```bash
swift test
```

开发循环（监听 `Package.swift`、`Sources/`、`Tests/`，变更后自动重编译并重启）：

```bash
./Scripts/dev.sh
```

开发循环日志写入：

```text
Artifacts/DevRunner/clawbar-dev.log
```

可选轮询间隔：

```bash
CLAWBAR_DEV_POLL_INTERVAL=0.5 ./Scripts/dev.sh
```

覆盖率检查：

```bash
./Scripts/check_coverage.sh
```

Smoke test（会构建、启动 smoke harness，并生成截图与日志）：

```bash
./Scripts/smoke_test.sh
```

默认产物路径：

```text
Artifacts/SmokeTests/hello-world-smoke.png
Artifacts/SmokeTests/clawbar-smoke.log
```

完整测试流程：

```bash
./Scripts/test.sh
```

## 仓库结构

- `Sources/ClawbarKit`：共享的生命周期、配置、菜单模型等可测试逻辑。
- `Sources/Clawbar`：App 入口、SwiftUI / AppKit 集成，以及 OpenClaw 安装、Gateway、Provider、Channels、TUI 等流程。
- `Tests/ClawbarTests`：XCTest 测试。
- `Scripts/`：开发、测试、覆盖率和 smoke test 脚本。
- `Artifacts/`：运行日志和测试产物。
- `docs/`：设计说明、调查记录和排障文档。
- `References/openclaw`：固定提交的 OpenClaw 参考快照。

## OpenClaw 参考工作流

凡是涉及 OpenClaw 内部行为、CLI 参数、Gateway / Channel 协议、配置格式或 API 假设的修改，优先阅读 `References/openclaw`，不要只凭记忆或旧笔记实现。

- `References/openclaw` 是 vendored snapshot，不是开发目录。
- 如果当前任务依赖最新的 OpenClaw 接口，先同步参考快照，再修改 Clawbar。
- 参考快照更新应尽量和 Clawbar 行为改动分开提交，除非任务本身就是做 reference sync。

## 项目技能

本仓库把项目相关 skills 放在 `.agents/skills/`，并通过 `.agents/skills/registry.json` 管理，不依赖全局机器状态。

常用命令：

```bash
python3 Scripts/project_skills.py list
python3 Scripts/project_skills.py check
python3 Scripts/project_skills.py sync
```

如果 Clawbar 或 OpenClaw 行为异常，优先使用项目本地的 `clawbar-openclaw-logs` skill 收集当前日志，再继续判断问题。
