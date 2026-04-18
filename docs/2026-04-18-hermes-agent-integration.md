# Clawbar 支持 Hermes Agent 设计方案

- 飞书文档（权威版本，含完整章节）: https://www.feishu.cn/docx/IKGrdCHP3oXh2xxiRf8lkpHqg9b
- 分支: `feature/hermes-agent-support`
- 参考快照: `References/openclaw`、`References/hermes-agent`

## 摘要

把 Clawbar 从"OpenClaw 管家"升级为"本机多 Agent 运行时管家"，Hermes Agent 作为第一个并入的 peer runtime。引入最小化的 `AgentRuntime` 协议（+ `ProviderCapable` / `ChannelCapable` / `MessagingGatewayCapable` / `TUILaunchable` 可选子协议），不做 registry / 插件系统。Hermes 安装走 `uv tool install hermes-agent`，配置与状态在 `~/.hermes/` 与 `~/.openclaw/` 物理隔离，菜单以 Agent 为第一维度并列展示。

## 关键决策

1. **定位**: Hermes 是和 OpenClaw 同级的 Agent runtime，**不是** OpenClaw 的 Provider。
2. **抽象**: 薄 `AgentRuntime` 协议 + 能力子协议；不搞 registry。
3. **安装**: `uv tool install hermes-agent`（缺 `uv` 时引导安装）。不绑定 Python 运行时到 `.app`。
4. **Provider**: 复用 `ProviderKind`，每个 runtime 各自生成 save plan；Hermes 不支持的品牌在面板里隐藏。
5. **Gateway 术语**: OpenClaw 的 Gateway = 核心进程；Hermes 的 Messaging Gateway = 消息平台网关。UI 必须明确区分。
6. **多平台向导**: Hermes 的 Discord/Slack/Feishu 等配置初期不做 UI，入口点 `hermes gateway setup` 跑在 Terminal。
7. **不做**: 跨 runtime 数据互通、Python FFI、内嵌 ACP client、Skill marketplace UI。

## 落地阶段

| Phase | 范围 |
| --- | --- |
| P0 | 抽象落地：`AgentRuntime` + 菜单 Agents 分组占位 |
| P1 | Hermes 安装 + 状态读取 |
| P2 | Hermes Provider（OpenAI / Anthropic / OpenRouter / Ollama / Custom） |
| P3 | Hermes Messaging Gateway install/start/stop + 打开配置 |
| P4 | TUI 启动器 + 文档同步 |
| P5（可选） | 内置 ACP client（独立设计） |

完整章节（现状分析、模块图、save plan 示例、风险、开放问题、不做的事清单等）见飞书文档。
