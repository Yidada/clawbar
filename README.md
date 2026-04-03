# clawbar

一个参考 [CodexBar](https://github.com/steipete/CodexBar) 结构、但只保留最小能力的 macOS 菜单栏示例。

当前版本只有最基础的 Hello World：

- 启动后在菜单栏显示一个图标
- 点击图标后看到 `Hello World`
- 提供 `Quit` 退出入口

## Requirements

- macOS 14+
- Xcode 26+ 或 Swift 6.3+

## Run

```bash
swift run Clawbar
```

## Dev Loop

保存后自动重编译并重启 app：

```bash
./Scripts/dev.sh
```

说明：

- 这是自动重启，不是运行时代码热替换
- 脚本会监听 `Package.swift`、`Sources/`、`Tests/`
- 编译失败时不会重启 app，会保留当前版本并等待下一次修改
- 日志输出到 `Artifacts/DevRunner/clawbar-dev.log`

可选：

```bash
CLAWBAR_DEV_POLL_INTERVAL=0.5 ./Scripts/dev.sh
```

## Build

```bash
swift build
```

## Test Harness

### Unit tests

运行所有单元测试：

```bash
swift test
```

带覆盖率运行，并检查 `ClawbarKit` 的函数级覆盖率门槛：

```bash
./Scripts/check_coverage.sh
```

说明：

- `ClawbarKit` 是业务逻辑层，覆盖率 gate 绑定在这里
- 菜单栏 UI 本身保持很薄，主要通过 smoke harness 验证

### Smoke tests

运行冒烟测试并产出关键路径截图：

```bash
./Scripts/smoke_test.sh
```

默认会生成：

- `Artifacts/SmokeTests/hello-world-smoke.png`
- `Artifacts/SmokeTests/clawbar-smoke.log`

### Full harness

一次性跑完整 harness：

```bash
./Scripts/test.sh
```
