# 项目级 Skills 整理方案

## 背景

`clawbar` 已经把项目级 skill 放在 `.agents/skills/`，但如果每个 skill 自己维护 build、start、stop、logs、diagnostics 逻辑，就会重新长出一套隐性的脚本系统。

这次整理的目标不是减少 skill 数量，而是把 skill 和统一执行面绑定起来，让 Agent 能直接从 skill 文档跳到真实可执行入口。

## 决策

`clawbar` 的 skill source of truth 固定为仓库内的 `.agents/skills/`。

规则如下：

- 项目自有 skill 直接维护在 `.agents/skills/<skill-name>/`
- 如果某个全局 skill 变成项目依赖，先登记到 `.agents/skills/registry.json`
- 外部 skill 需要 vendor 到仓库，而不是只存在于 `~/.codex/skills` 或 `~/.agents/skills`
- 项目文档、脚本和自动化默认只能依赖仓库内 skill
- skill 不应再各自实现一套 app lifecycle；统一调用 `python3 Tests/Harness/clawbarctl.py ...`

## 当前清单

清单定义在 `.agents/skills/registry.json`，当前已登记的项目自有 skill：

- `clawbar-dev-loop`
- `clawbar-menubar-screenshot`
- `clawbar-menubar-verify`
- `clawbar-openclaw-logs`

分类：

- `development`
- `visual-regression`
- `ui-verification`
- `diagnostics`

## 管理命令

新增脚本：`python3 Scripts/project_skills.py`

常用命令：

```bash
python3 Scripts/project_skills.py list
python3 Scripts/project_skills.py check
python3 Scripts/project_skills.py sync
python3 Scripts/project_skills.py sync <skill-name>
```

说明：

- `list`：查看 manifest 中登记的项目 skill
- `check`：检查 manifest 和本地 `.agents/skills/` 是否一致
- `sync`：把 manifest 中标记为 `vendored` 的外部 skill 复制进仓库

## 当前执行面约定

skills 负责告诉 Agent “什么时候做什么”，但不再各自维护底层运行入口。当前统一约定：

- 开发循环：`python3 Tests/Harness/clawbarctl.py app dev-loop`
- app 启动/停止/重启：`python3 Tests/Harness/clawbarctl.py app ...`
- unit / smoke / integration：`python3 Tests/Harness/clawbarctl.py test ...`
- diagnostics：`python3 Tests/Harness/clawbarctl.py logs collect`

这样做的目的不是减少 skill，而是让 skill 的说明层和脚本层都能复用同一套 artifact、日志、状态追踪布局。

## 新增外部 Skill 的流程

1. 在 `.agents/skills/registry.json` 新增一个 `mode: "vendored"` 的条目
2. 配置 `source` 或 `upstreamName`
3. 运行 `python3 Scripts/project_skills.py sync <skill-name>`
4. 运行 `python3 Scripts/project_skills.py check`
5. 如有必要，更新 `AGENTS.md` 说明这个 skill 在项目中的触发条件

一个最小 vendored 条目示例：

```json
{
  "name": "example-skill",
  "mode": "vendored",
  "category": "tooling",
  "purpose": "Explain why this skill is project-relevant.",
  "upstreamName": "example-skill"
}
```

默认查找源包括：

- `$CODEX_HOME/skills`
- `~/.agents/skills`
- `~/.codex/plugins/cache/openai-curated/*/*/skills`

## 预期效果

整理完成后，这个仓库里的 skill 管理会变成：

- 可见：哪些 skill 真的属于项目，一眼能查
- 可复制：换一台机器也能按 manifest 补齐
- 可审计：不会再默认依赖个人全局目录里的隐式 skill
- 可演进：后续新增 skill 时，有固定入口和同步流程
- 可读：skill 文档和实际执行入口不再漂移，Agent 能直接从文档跳到统一 harness
