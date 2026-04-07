# Clawbar 成功/失败反馈增强方案

## 背景

当前 Clawbar 并不是没有反馈，而是反馈信息分散在各个 manager 和 view 里，缺少统一的“操作结果层”：

- 安装流程主要依赖 `OpenClawInstaller.statusText/detailText` 和独立日志窗口。
- Gateway、Provider、WeChat 分别维护自己的 `lastActionSummary/lastActionDetail`。
- Feishu 把阶段状态塞进 `snapshot.summary/detail/logSummary`。
- 菜单栏主面板更偏向“系统健康概览”，不是“最近一次操作结果”面板。

这会带来几个体验问题：

1. 成功反馈不够明显。多数成功状态只是某一段文案变了，缺少视觉上明确的“已完成”反馈。
2. 失败反馈不够聚焦。失败时往往能看到错误文字，但不总能立即知道“下一步该做什么”。
3. 长流程反馈不连续。安装、扫码、OAuth、Gateway 重启这类流程会跨多个阶段，用户容易丢失上下文。
4. 反馈风格不一致。不同页面使用不同字段、不同文案密度、不同停留时长，用户难以建立预期。
5. 菜单栏场景下结果容易丢。用户发起动作后如果收起面板，完成/失败时没有一个足够醒目的回流提示。

## 目标

- 让用户在 1 秒内看懂“刚才发生了什么”。
- 让用户在 3 秒内看懂“现在成功了、失败了，还是部分完成”。
- 失败时必须直接给出下一步动作，而不是只给错误文本。
- 保持现有 manager 逻辑基本不散掉，在当前代码结构上渐进接入。
- 让菜单栏主面板、管理窗口、独立安装页共享同一套反馈语义。

## 非目标

- 这次不重做整套视觉主题。
- 这次不引入复杂通知中心或完整任务历史中心。
- 这次不要求所有 OpenClaw CLI 输出结构化；允许先基于现有 summary/detail/log 输出适配。

## 对现状的判断

从代码结构看，Clawbar 已经有“状态数据”，但缺少“结果表达”：

- [Sources/Clawbar/OpenClawInstaller.swift](/Users/benjamin/Workspace/Stir/clawbar/Sources/Clawbar/OpenClawInstaller.swift) 已能区分安装成功、失败、Gateway 未就绪等状态，但 UI 主要是文本切换。
- [Sources/Clawbar/GatewayManagementView.swift](/Users/benjamin/Workspace/Stir/clawbar/Sources/Clawbar/GatewayManagementView.swift) 和 [Sources/Clawbar/ProviderManagementView.swift](/Users/benjamin/Workspace/Stir/clawbar/Sources/Clawbar/ProviderManagementView.swift) 有 action summary/detail，但表现层较弱，且缺少统一 CTA。
- [Sources/Clawbar/ChannelsManagementView.swift](/Users/benjamin/Workspace/Stir/clawbar/Sources/Clawbar/ChannelsManagementView.swift) 对扫码中间态表达较完整，但完成态和失败态仍偏“说明文本”，不够像明确的结果反馈。
- [Sources/Clawbar/MenuContentView.swift](/Users/benjamin/Workspace/Stir/clawbar/Sources/Clawbar/MenuContentView.swift) 更像总览页，适合展示“当前整体健康”，不适合直接承载复杂操作结果。

结论：问题不在于缺状态，而在于缺一层统一的 feedback model 和统一的反馈组件。

## 方案总览

建议引入“两层反馈”而不是单纯加 toast：

1. 页面内状态层
   用于展示操作进行中、部分完成、阻塞原因和下一步动作。
2. 全局结果层
   用于展示“刚刚成功/失败”的强反馈，跨页面统一样式，并可在菜单栏场景下短暂保留。

核心判断：

- 仅靠 inline 文案不够醒目。
- 仅靠 toast 又不够稳，因为菜单栏/长流程场景下 toast 太容易错过。
- 最合适的是“inline 状态卡 + 顶部结果 banner + 必要时系统通知”的组合。

## 统一反馈模型

建议新增一个统一模型 `OperationFeedback`，由各 manager 在关键动作完成时上报：

```swift
struct OperationFeedback: Identifiable, Equatable, Sendable {
    enum Level: Sendable {
        case progress
        case success
        case warning
        case failure
        case info
    }

    enum Source: Sendable {
        case install
        case gateway
        case provider
        case channelFeishu
        case channelWeChat
        case menuPanel
    }

    let id: UUID
    let source: Source
    let level: Level
    let title: String
    let message: String
    let recoverySuggestion: String?
    let primaryActionTitle: String?
    let secondaryActionTitle: String?
    let logHint: String?
    let createdAt: Date
    let autoDismissAfter: TimeInterval?
    let isSticky: Bool
}
```

设计重点：

- `progress` 和 `success/failure` 分开，避免“处理中”和“已完成”复用同一段文案。
- `warning` 用于“部分成功”，例如 OpenClaw 安装完成但 Gateway 未就绪。
- `recoverySuggestion` 单独建字段，避免错误信息和修复建议混在一起。
- `autoDismissAfter` 只给成功态使用；失败态默认 sticky。

## 反馈容器

建议新增一个轻量中心对象 `OperationFeedbackCenter`，负责：

- 接收各 manager 发出的反馈事件。
- 保存“当前活跃反馈”和“最近一次结果反馈”。
- 控制成功态自动消失、失败态驻留、同源事件覆盖等规则。
- 为菜单栏主面板和管理页提供统一订阅入口。

建议放置位置：

- 先放在 `Sources/Clawbar/`，因为它明显偏 UI 协调层。
- 等模式稳定后，再评估是否抽到 `ClawbarKit`。

## 展示策略

### 1. 页面顶部 Banner

适用页面：

- Gateway 管理页
- Provider 管理页
- Channels 管理页
- OpenClaw 安装页

行为：

- 成功：绿色或品牌强调色，显示 4 到 6 秒后自动消失。
- 失败：红/橙色，默认不自动消失。
- 警告：橙色，默认停留更久，并展示下一步建议。
- 进行中：不走顶部 banner，仍放在操作区域内，避免用户看到重复 loading。

内容结构：

- 第一行：明确结果，例如“Gateway 已重启”“Provider 保存失败”
- 第二行：一句原因或结果描述
- 右侧动作：`查看日志`、`重试`、`打开对应页面`

### 2. 操作区内状态卡

当前大部分页面已经有 summary/detail，建议升级为统一的状态卡视觉，而不是纯文字：

- 带图标和颜色语义。
- 明确区分“处理中 / 成功 / 警告 / 失败”。
- 允许展示最多一个下一步动作按钮。

示例：

- 安装中：显示进度态和“正在执行官方安装脚本”
- 安装完成但 Gateway 未就绪：显示 warning 卡和“前往 Gateway 页检查服务状态”
- WeChat 已扫码待确认：显示 progress 卡和“请在手机微信确认授权”

### 3. 菜单栏结果回流

菜单栏主面板不建议塞入完整日志，但应该能看见最近一次明确结果。

建议在 `MenuContentView` 顶部摘要区域增加一条短反馈：

- 成功：`刚刚完成：OpenClaw 安装完成`
- 失败：`最近失败：Gateway 启动失败`
- 警告：`最近提醒：Gateway 服务未就绪`

行为：

- 只展示最近一次非 progress 反馈。
- 成功态可在 30 到 60 秒后淡出。
- 失败/警告保留到下一次同源成功覆盖，或用户手动关闭。

这样即使用户关掉过某个管理页，回到菜单栏也能知道最近结果。

### 4. 系统通知

系统通知建议只在两类场景使用：

- 用户触发长流程后关闭了面板/窗口。
- 流程跨外部应用，例如 Terminal、浏览器、扫码授权。

建议只做可选增强，不作为第一阶段必做项。否则会过度打扰。

## 状态分级规则

统一分级规则应先收敛，不要每个 manager 自己决定颜色语义。

### 成功

- 命令完成且用户目标达成。
- 示例：Gateway 已启动、Provider 已写入、微信连接成功、Feishu channel 已启用。

### 警告

- 主操作完成，但后续仍有阻塞或需要人工处理。
- 示例：OpenClaw 安装完成但 Gateway 未安装；Provider 已写入但认证仍未生效。

### 失败

- 当前目标未达成，且需要用户重新操作或排查。
- 示例：CLI 超时、命令非零退出、二维码授权失败、状态解析失败。

### 进行中

- 用户动作已被接受，正在处理中。
- 示例：正在安装微信能力、正在轮询 Feishu 授权、正在等待 ChatGPT OAuth。

## CTA 设计

失败反馈如果没有 CTA，用户仍然不知道怎么处理。

建议 CTA 固定收敛到以下几类：

- `重试`
- `查看日志`
- `打开浏览器`
- `前往 Gateway`
- `前往 Channels`
- `前往 Provider`

不要在 banner 里放过多按钮，最多两个。

## 文案规范

建议统一文案结构：

- 标题：一句话说结果，不要超过 18 个汉字。
- 描述：补充原因或状态，不要重复标题。
- 下一步：用动作句，不写成说明文。

推荐模板：

- 成功：`[对象]已[完成动作]`
- 失败：`[对象][动作]失败`
- 警告：`[对象]已完成，但[阻塞项]`
- 处理中：`正在[动作]...`

示例：

- `Gateway 已重启`
- `Provider 保存失败`
- `OpenClaw 已安装，但 Gateway 未就绪`
- `正在等待微信扫码确认...`

## 与现有代码的接入方式

建议分三步做，避免一次性重构全部 manager。

### 第一阶段：加统一反馈层，不改核心流程

- 新增 `OperationFeedback` 和 `OperationFeedbackCenter`
- 新增通用 `OperationFeedbackBanner`
- 先接入 Gateway、Provider、Installer

原因：

- 这三块反馈模型相对简单，已经有明确的成功/失败边界
- 可以先把 UI 模式跑通

### 第二阶段：接入 Channels 长流程

- WeChat 安装/扫码/绑定
- Feishu 扫码/安装/启用/诊断

这里重点不是“有没有状态”，而是把阶段状态映射到统一 feedback level。

### 第三阶段：菜单栏摘要和系统通知

- 在 `MenuContentView` 顶部接入最近一次结果反馈
- 对跨窗口长流程增加可选系统通知
- 用 `ClawbarEventLogger` 增加 feedback 事件埋点

## 与现有 manager 的映射建议

### OpenClawInstaller

- 继续保留 `statusText/detailText/logText`
- 但在 install/update/uninstall 完成时额外发送统一反馈
- `安装完成但 Gateway 未就绪` 映射为 `warning`

### OpenClawGatewayManager

- 保留 `lastActionSummary/lastActionDetail`
- 在 `perform(_:)` 结束时把 `OpenClawGatewayActionFeedback` 转成统一反馈
- 成功自动消失，失败 sticky

### OpenClawProviderManager

- `Provider 已写入` 映射为成功
- `OpenAI Codex 登录启动失败` 映射为失败
- `等待 OpenAI Codex 登录完成` 只保留 inline，不发全局成功/失败，直到轮询真正结束

### OpenClawChannelManager / OpenClawFeishuChannelManager

- 扫码中、等待确认、轮询中属于 progress
- 已连接/已启用属于 success
- 二维码过期、安装器失败、doctor 不健康属于 warning 或 failure，具体按是否阻塞主目标决定

## 测试建议

建议补三类测试，而不是只看肉眼效果：

1. manager 到 feedback model 的映射测试
   覆盖成功、失败、warning、progress
2. banner 展示规则测试
   覆盖 auto-dismiss、sticky、同源覆盖、最近结果保留
3. smoke/harness 回归
   覆盖典型动作后的可见反馈文案和事件日志

特别建议把 `ClawbarEventLogger.emit(...)` 用起来，输出类似事件：

```text
CLAWBAR_EVENT feedback_shown source=gateway level=failure title="Gateway 启动失败"
CLAWBAR_EVENT feedback_dismissed source=provider level=success title="Provider 已写入"
```

这样 smoke test 不一定非要靠截图比对，也能验证关键反馈是否出现。

## 风险与取舍

### 不建议只加 Toast

原因：

- 菜单栏场景下容易错过
- 长流程完成时用户可能不在当前视图
- 失败信息通常需要 CTA 和更长停留时间

### 不建议直接把日志变成主反馈

原因：

- 日志适合排查，不适合作为第一反馈
- 用户首先需要的是结论和下一步，不是原始输出

### 不建议每个页面各做一套

原因：

- 当前已经出现字段和文案分散的问题
- 如果继续各做各的，后面维护成本会更高

## 推荐实施顺序

1. 定义统一 feedback model 和 center
2. 做一个通用 banner + 一个通用 inline status card
3. 先接入 Gateway / Provider / Installer
4. 再接入 WeChat / Feishu 长流程
5. 最后给菜单栏主面板加“最近结果”摘要
6. 视体验再决定是否补系统通知

## 预期效果

做完这一轮后，用户的主观感受应该从“有状态，但看不清结果”变成：

- 点完按钮，立刻知道系统接受了操作
- 操作结束，立刻知道成功还是失败
- 失败时，立刻知道下一步点哪里
- 回到菜单栏，也能看到最近一次关键结果

这比单纯继续堆 `statusText` 或 `lastActionDetail` 更有效，也更符合 Clawbar 作为菜单栏控制面的使用方式。
