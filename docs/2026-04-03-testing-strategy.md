# 自动化测试与验证策略

## 目标

把本地开发、自动化验证和日志排查统一到一个可读、可组合、可追踪的入口上，让 Agent 和开发者都不需要再记忆分散脚本。

当前统一入口：

```bash
python3 Tests/Harness/clawbarctl.py ...
```

顶层 `Scripts/*.sh` 仍然保留，但已经只是兼容 wrapper。

## 当前测试分层

### 1. Unit

命令：

```bash
python3 Tests/Harness/clawbarctl.py test unit
python3 Tests/Harness/clawbarctl.py test unit --coverage-gate
```

职责：

- 纯逻辑验证
- 配置和状态机分支验证
- 环境变量分支验证
- OpenClaw manager / provider / gateway / channel 的可注入命令流验证

`--coverage-gate` 会对 `Sources/ClawbarKit` 做函数级覆盖率闸门，并把结果写入 run artifact。

### 2. Smoke

命令：

```bash
python3 Tests/Harness/clawbarctl.py test smoke
```

职责：

- 构建并启动 app
- 在 `CLAWBAR_SMOKE_TEST=1` 模式下打开固定 smoke window
- 截图
- 验证关键生命周期日志

当前 smoke 不只是截图，还会断言 app log 里出现：

- `CLAWBAR_EVENT app.launch`
- `mode=smokeTest`
- `CLAWBAR_EVENT smoke.window.shown`

这样 smoke 失败时可以同时看截图和日志，而不是只能靠 GUI 现象判断。

### 3. Integration

命令：

```bash
python3 Tests/Harness/clawbarctl.py test integration --suite all
```

当前 integration suite 是“按产品能力分组的 XCTest 运行面”，用于把高层流程按业务域回归，而不是引入一套完全独立的新测试框架。

已登记分组：

- `feishu`
- `wechat`
- `provider`
- `gateway`
- `installer`

这些 suite 会分别输出独立 log，方便 Agent 只重跑受影响的能力域。

### 4. Aggregate

命令：

```bash
python3 Tests/Harness/clawbarctl.py test all
```

默认顺序：

1. unit + coverage gate
2. smoke
3. integration(all)

## Artifact 与可读性约定

所有 harness 运行产物都在：

```text
Artifacts/Harness/Runs/<timestamp>-<label>/
```

约定：

- 每次运行都有 `summary.json`
- 单测有 `swift-test.log`
- smoke 有 `clawbar-smoke.log` 和截图
- integration 按 suite 拆分日志
- 运行中的 app 状态保存在 `Artifacts/Harness/State/app-state.json`

这套结构的目标是让 Agent 在失败时先看 artifact，而不是重新猜当前机器状态。

## UI Harness 的关系

菜单栏截图和菜单验证仍然使用 skill 自带的 Accessibility 辅助脚本：

- `press_status_item.swift`
- `verify_menu.swift`

但 app 的构建、启动、状态注入、重启和日志路径已经统一下沉到 harness：

```bash
python3 Tests/Harness/clawbarctl.py app start --mode ui ...
```

这样 UI skill 不再维护第二套启动逻辑。

## 日志验证

统一做法：

- 测试命令负责生成原始日志文件
- `clawbarctl.py logs assert` 负责断言日志模式
- smoke 已默认启用关键日志断言
- 需要更细粒度日志检查时，可在后续扩展 `--log-contains` / `--log-absent`

诊断收集命令：

```bash
python3 Tests/Harness/clawbarctl.py logs collect
```

它会同时抓取：

- 当前 app state
- 最近 harness summaries
- Clawbar / OpenClaw 用户日志
- `/tmp/openclaw` runtime log
- `~/.openclaw/logs`
- macOS unified log

## 后续方向

- 如果后续需要“点击安装 OpenClaw / 打开窗口 / 校验安装日志”的更强 UI smoke，继续在现有 AX 辅助脚本上扩展，不要再引入第三套启动脚本
- 如果新增能力域（例如新的 provider/channel），先把对应 XCTest 归入 integration suite，再更新 harness suite mapping 和本文档
