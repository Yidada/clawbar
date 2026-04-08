# 2026-04-08 Feishu Channel 高级权限设置设计

## 背景

当前 `ChannelsManagementView` 的飞书卡片主要覆盖安装、扫码绑定、启停和日志，不直接暴露 Feishu Channel 的权限策略编辑入口。对应逻辑在 `OpenClawFeishuChannelManager` 中会在安装后写入默认策略（例如 `dmPolicy=open`、`groupPolicy=open`、`allowFrom` 含 `*`）。

用户反馈希望新增「高级设置」，默认折叠，在需要时展开并精细控制权限。

## 调研结论

### Clawbar 现状（本仓库源码）

- Feishu 卡片当前没有「高级设置」模块，只有绑定、启停和日志 UI。  
- 安装后默认写入：
  - `channels.feishu.dmPolicy = "open"`
  - `channels.feishu.allowFrom`（包含 `*`，并在扫码场景合并 owner open_id）
  - `channels.feishu.groupPolicy = "open"`
  - `channels.feishu.groups["*"].enabled = true`
  - `channels.feishu.groups["*"].requireMention = false`
- 单测已经覆盖上述配置写入路径，验证命令序列与 JSON 载荷。

### OpenClaw 官方文档（Feishu Channel）

- 私信侧：
  - `channels.feishu.dmPolicy` 默认 `pairing`。
  - `channels.feishu.allowFrom` 用于私信 sender allowlist（open_id）。
- 群聊侧：
  - `channels.feishu.groupPolicy` 支持 `open` / `allowlist` / `disabled`。
  - `channels.feishu.groupAllowFrom` 控制允许的群（chat_id）列表。
  - `channels.feishu.groups.<chat_id>.allowFrom` 可细化到群内允许的发送者 open_id。

> 参考：<https://docs.openclaw.ai/zh-CN/channels/feishu>

## 目标

在 Feishu Channel 卡片中新增「高级设置」折叠面板，默认收起，支持分别配置：

1. Group Policy（群聊权限）
2. DM Policy（私信权限）

每个策略提供 3 档：

- 仅自己（Only Me）
- 指定 UID（Selected UIDs）
- 全开放（Open）

## 交互设计

### 1) 信息架构

在飞书卡片 `Button(feishuManager.bindingActionTitle)` 下方、日志 `DisclosureGroup` 上方新增：

- `DisclosureGroup("高级设置")`（默认 `isExpanded = false`）
- 面板内容分两块：
  - `Group 权限`
  - `DM 权限`

每块结构一致：

- 策略单选（3 个 Segmented/Radio）
- 若选「指定 UID」，显示 UID 多值输入区（token/tag 输入）
- 底部显示当前将写入的 OpenClaw 配置预览（只读 monospace）
- 「保存高级设置」按钮（busy 时禁用）

### 2) 策略文案建议

- Group
  - 仅自己：仅允许 owner 的 open_id 在群中触发机器人
  - 指定 UID：仅允许名单内 open_id 在群中触发机器人
  - 全开放：群里所有成员都可触发机器人
- DM
  - 仅自己：仅允许 owner 的 open_id 私信机器人
  - 指定 UID：仅允许名单内 open_id 私信机器人
  - 全开放：所有用户都可私信机器人

### 3) 默认态与兼容

- 默认折叠，不打断现有「开箱即用」路径。
- 首次展开时读取并回填当前配置（不是硬编码默认值）。
- 若读取失败，显示 warning 并提供「按推荐值重置」快捷操作。

## 配置映射（核心）

> 下表是 Clawbar UI 与 OpenClaw 配置键的映射建议，优先满足“用户用 UID 认知权限”。

### DM 权限映射

- Only Me
  - `channels.feishu.dmPolicy = "allowlist"`
  - `channels.feishu.allowFrom = [ownerOpenID]`
- Selected UIDs
  - `channels.feishu.dmPolicy = "allowlist"`
  - `channels.feishu.allowFrom = [uids...]`
- Open
  - `channels.feishu.dmPolicy = "open"`
  - `channels.feishu.allowFrom` 可保留现值；建议至少包含 `"*"`

### Group 权限映射

为尽量贴合“按 UID 控制谁能在群里说话”的用户心智，建议基于 `groups."*".allowFrom` 实现 sender 级权限：

- Only Me
  - `channels.feishu.groupPolicy = "open"`
  - `channels.feishu.groups["*"].allowFrom = [ownerOpenID]`
- Selected UIDs
  - `channels.feishu.groupPolicy = "open"`
  - `channels.feishu.groups["*"].allowFrom = [uids...]`
- Open
  - `channels.feishu.groupPolicy = "open"`
  - 清理 `channels.feishu.groups["*"].allowFrom`

补充：若后续需要控制“允许哪些群（chat_id）”，可在高级设置二期中增加 `groupAllowFrom`。

## 运行时/状态机建议

### 新增 Manager 能力

在 `OpenClawFeishuChannelManager` 增加两类 API：

1. `loadAdvancedPolicySnapshot()`
   - 读取并解析：
     - `channels.feishu.dmPolicy`
     - `channels.feishu.allowFrom`
     - `channels.feishu.groupPolicy`
     - `channels.feishu.groups`
   - 归一化为 UI 模型（`onlyMe | selected | open` + uid 列表）。

2. `saveAdvancedPolicy(_ draft)`
   - 校验 UID 列表非空（selected 模式）
   - 生成最小写入命令集
   - 顺序执行 `openclaw config set ... --strict-json`
   - 成功后刷新 `refreshStatus()` 并回显日志

### 数据模型建议

新增可测试、可序列化模型：

- `FeishuAdvancedPolicySnapshot`
- `FeishuPermissionMode`（`onlyMe`, `selected`, `open`）
- `FeishuAdvancedPolicyDraft`

并将“配置映射”逻辑做成纯函数，便于 XCTest 覆盖。

## 验证与测试建议

1. 单元测试（优先）
- 模式到配置键写入映射测试
- 现有配置到 UI 模式反解析测试
- selected 模式空列表校验测试

2. 管理器命令序列测试
- 复用现有 `MockCommand` 模式
- 验证 `config set` 命令路径与 JSON 载荷

3. Smoke/UI
- 展开/收起高级设置不影响现有安装绑定流程
- 在 busy 状态下按钮禁用正确

## 实施分期

### Phase 1（本次目标）
- 加 UI 折叠面板
- 支持 Group/DM 三档策略 + UID 输入
- 支持读取/保存配置
- 补齐单元测试

### Phase 2（可选）
- 增加 `groupAllowFrom`（按 chat_id 白名单）
- 增加 `requireMention` 细粒度控制
- 增加“导入当前日志中最近出现的 open_id/chat_id”辅助能力

## 风险与回滚

- 风险：对现有默认开放策略的行为改变可能影响已上线用户。
- 缓解：
  - 默认仍保持高级设置折叠
  - 保存前展示“将写入配置预览”
  - 提供“一键恢复推荐默认值”（当前 Clawbar 默认）
- 回滚：仅需撤回高级设置写入入口，不影响已存在启停/绑定主流程。
