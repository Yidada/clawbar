# 自动化测试方案调研

## 目标

为 `clawbar` 建立一套可持续演进的自动化测试方案，重点覆盖两层：

- Unit test：快速验证业务逻辑和状态分支
- Smoke test：验证 app 能启动，核心功能执行链路能走通

这份方案基于当前仓库现状整理，而不是从零假设。

## 当前现状

### 已有 Unit test

当前单测已经覆盖一批核心逻辑：

- `ClawbarKit/AppConfiguration`
- `ClawbarKit/AppLifecycle`
- `ClawbarKit/MenuContentModel`
- `Clawbar/OpenClawInstaller` 的纯逻辑部分
- `Clawbar/AppDelegate`

本地基线结果：

- `swift test` 已通过
- 当前共有 34 个测试

### 已有 Smoke test

当前 `Scripts/smoke_test.sh` 已具备以下能力：

- `swift build`
- 启动 `Clawbar`
- 通过 `CLAWBAR_SMOKE_TEST=1` 让 app 打开一个固定 smoke 窗口
- 通过 `CGWindowList` 找到 smoke 窗口
- 截图并输出 artifact

这层 smoke 的优点是稳定、无外部依赖、适合截图留档；但它的问题也很明确：

- 它没有点击菜单栏主入口
- 它没有验证菜单弹层真实内容
- 它没有覆盖“点击安装 OpenClaw”这条主流程

### 已有可复用能力

仓库里已经有一套更接近真实用户路径的 UI harness，可以直接复用：

- `.agents/skills/clawbar-menubar-screenshot/scripts/press_status_item.swift`
- `.agents/skills/clawbar-menubar-screenshot/scripts/verify_menu.swift`
- `.agents/skills/clawbar-menubar-screenshot/scripts/verify-menubar.sh`

这套脚本已经能做到：

- 启动 app 到 `CLAWBAR_UI_TEST=1` 模式
- 通过 macOS Accessibility API 找到菜单栏图标
- 打开菜单栏弹层
- 校验弹层中是否出现预期文案

本地基线结果：

- `./.agents/skills/clawbar-menubar-screenshot/scripts/verify-menubar.sh` 已通过

这意味着当前仓库并不缺“UI 自动化底座”，缺的是：

- 从“只读验证”扩展到“点击驱动”
- 为安装流程注入可测试、无副作用的 fake 行为
- 补齐主流程断言

## 推荐方案

建议保留“两层测试”结构，不要把所有验证都堆到 UI 层。

推荐原则：

- Unit test 负责覆盖“分支和细节”
- Smoke test 负责覆盖“核心功能是否真的能执行”

### 第一层：Unit test

职责：

- 验证纯逻辑
- 验证状态切换
- 验证环境变量分支
- 验证文本映射和 UI 配置生成

建议继续把这层作为主力回归测试，保持快、稳定、无 GUI 依赖。

建议补强的点：

- 把 `MenuContentView` 中的状态分支继续向可测试模型收敛
- 把安装流程中的状态变化抽到更明确的状态机或 view model
- 给“安装中 / 安装成功 / 安装失败 / 已安装 / 未安装”补完整单测
- 给安装窗口文案和展示条件补单测，而不是只靠 smoke 观察

推荐方向不是直接测 SwiftUI View 树，而是继续测试驱动 View 的模型和状态对象。

### 第二层：Smoke test

职责：

- 验证 app 可以启动
- 验证菜单栏入口可以被打开
- 验证核心功能点击路径可以走通
- 验证关键功能执行后的结果出现

这里建议拆成两类 smoke：

- 静态 smoke：保留现有 `Scripts/smoke_test.sh`，用于固定窗口截图和最基础启动验收
- 交互 smoke：新增基于 Accessibility 的主流程脚本，只覆盖核心功能执行链路

不建议让 smoke 承担太多细碎 UI 断言，例如：

- 所有文案逐字匹配
- 所有辅助字段都出现
- 所有边界状态都从 UI 层回归

这些更适合留给 unit test。

## 冒烟测试主流程建议

针对当前产品形态，smoke 建议优先覆盖“功能执行”而不是“展示完整性”。

建议先覆盖一条主链路，再补一条状态分支。

### 路径 A：未安装 OpenClaw

这是当前最关键的点击主流程。

建议步骤：

1. 以 `CLAWBAR_UI_TEST=1` 启动 app
2. 注入 `CLAWBAR_TEST_OPENCLAW_STATE=missing`
3. 通过 Accessibility 打开菜单栏弹层
4. 只校验菜单已成功展开，并存在 `安装 OpenClaw`
5. 点击 `安装 OpenClaw`
6. 校验 `OpenClaw 安装` 窗口出现
7. 校验窗口里至少出现安装状态区和日志区

这条链路验证的是：

- 菜单栏入口存在
- 主按钮可点击
- 点击后会打开安装窗口
- 安装流程被正确拉起

### 路径 B：已安装 OpenClaw

这是菜单分支的另一条关键路径。

建议步骤：

1. 以 `CLAWBAR_UI_TEST=1` 启动 app
2. 注入 `CLAWBAR_TEST_OPENCLAW_STATE=installed`
3. 打开菜单栏弹层
4. 校验 `OpenClaw` 区块存在
5. 校验 `安装 OpenClaw` 按钮不存在

这条链路验证的是安装状态切换后的菜单展示正确。

如果只能先做一条 smoke，我建议优先做路径 A，因为它真正覆盖了“功能执行”。

## 关键设计建议

### 1. 不要在 smoke 里真的执行安装脚本

这是最重要的一点。

当前 `MenuContentView` 点击安装后会调用 `installer.startInstallIfNeeded()`，而真实实现会执行：

- `curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard`

如果直接在 smoke 里点击这个按钮，会带来几个问题：

- 依赖外网
- 依赖远端脚本稳定性
- 会修改本机环境
- 失败原因难以归因
- 测试速度和稳定性都很差

所以建议为 UI 测试模式增加一个“假安装执行器”。

推荐做法：

- 给 `OpenClawInstaller` 引入可注入的 install runner
- 正常运行时使用真实 `Process`
- 测试运行时使用 fake runner

fake runner 只需要模拟这些结果：

- `started`
- `streaming logs`
- `success`
- `failure`

这样 smoke test 点击 `安装 OpenClaw` 后，就能稳定验证：

- 安装窗口是否弹出
- 状态文案是否切换到“安装中”
- 日志区域是否有输出
- 结束态是否能展示成功或失败

### 2. 复用现有 Accessibility 脚本，不要切到坐标驱动

当前仓库已经有：

- 用 AX 找菜单栏 item
- 打开菜单弹层
- 读取菜单项标题

这比截图 OCR 或纯坐标点击稳定得多。

建议新增两个小型辅助脚本，而不是推翻现有 harness：

- `click_menu_item.swift`
- `verify_window.swift`

职责可以很简单：

- `click_menu_item.swift`
  - 找到已展开菜单
  - 根据标题点击某个菜单项，比如 `安装 OpenClaw`
- `verify_window.swift`
  - 查找指定窗口标题
  - 读取窗口内少量关键元素
  - 返回成功或失败

这样主流程 smoke 可以完整串起来。

### 3. 给安装窗口补 Accessibility 标识

菜单层现在已经有稳定的 `accessibilityIdentifier`，这很好。

但安装窗口 `OpenClawInstallView` 当前还没有类似标识。对 smoke 来说，仅靠文本匹配可以先跑起来，但长期会偏脆弱；不过如果 smoke 只验证核心执行链路，需要的标识数量可以保持很少。

建议给这些元素补标识：

- 安装状态标题
- 日志内容区域

这样后续无论走 AX 校验还是更细颗粒度 UI 验证，都更稳。

### 4. 保持“deterministic test mode”

当前项目已经在做这件事，这是对的，应该继续强化。

已有环境变量能力：

- `CLAWBAR_SMOKE_TEST=1`
- `CLAWBAR_UI_TEST=1`
- `CLAWBAR_TEST_OPENCLAW_STATE=missing|installed`
- `CLAWBAR_TEST_OPENCLAW_BINARY_PATH=...`
- `CLAWBAR_TEST_OPENCLAW_DETAIL=...`
- `CLAWBAR_TEST_OPENCLAW_EXCERPT=...`

建议继续扩展：

- `CLAWBAR_TEST_INSTALL_MODE=success|failure|running`
- `CLAWBAR_TEST_INSTALL_LOG=...`

这样 smoke 就能覆盖点击后的功能执行结果，而不触发真实副作用。

## 建议落地结构

### 保留现有脚本

- `Scripts/check_coverage.sh`
- `Scripts/smoke_test.sh`

### 新增脚本

- `Scripts/smoke_menu_flow.sh`
  - 主流程冒烟入口
- `.agents/skills/clawbar-menubar-screenshot/scripts/click_menu_item.swift`
  - 点击菜单项
- `.agents/skills/clawbar-menubar-screenshot/scripts/verify_window.swift`
  - 校验安装窗口

### 更新总入口

建议把 `Scripts/test.sh` 逐步调整为：

1. `Scripts/check_coverage.sh`
2. `Scripts/smoke_test.sh`
3. `Scripts/smoke_menu_flow.sh`

其中第 3 步需要明确依赖：

- macOS 图形界面
- Accessibility 权限

如果后续要跑 CI，需要分层：

- 无头 CI 只跑 unit + coverage
- 本机或专用 macOS runner 跑 interactive smoke

## 建议的实施顺序

### Phase 1

先补方案里最值钱、最便宜的部分：

- 为安装流程增加 fake install runner
- 给安装窗口补 accessibility 标识
- 新增 `smoke_menu_flow.sh`
- 新增“未安装路径”的点击 smoke，只验证功能执行链路

### Phase 2

补齐另一条菜单分支：

- 已安装路径 smoke
- 安装成功 / 失败态的最小断言

### Phase 3

再考虑更进一步的质量建设：

- 截图比对
- 更多 UI 状态断言
- 将 AX helper 稳定封装为通用脚本

## 结论

最适合当前仓库的方案不是引入一整套重量级 UI 测试框架，而是：

- 继续让 `ClawbarKit` 和状态逻辑承担绝大多数单测
- 保留现有截图 smoke
- 在现有 Accessibility harness 基础上补一条“覆盖核心功能执行”的 smoke
- 通过 fake install runner 消除真实安装副作用

这样成本最低，和现有结构最匹配，也最容易稳定。

如果要进入实现阶段，第一步我建议先做这三件事：

1. 给 `OpenClawInstaller` 加 test-only fake install runner
2. 新增 `click_menu_item.swift`
3. 新增 `Scripts/smoke_menu_flow.sh`，先打通“未安装 -> 点击安装 -> 安装窗口出现”这条主流程
