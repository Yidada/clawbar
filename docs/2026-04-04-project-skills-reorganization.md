# 项目级 Skills 整理方案

## 背景

当前 `clawbar` 已经有项目级 `.agents/skills/`，但缺少统一清单和同步约定。结果是：

- 仓库内 skill 和全局 skill 的边界不清晰
- 哪些 skill 属于当前项目，没有一个可检查的来源
- 如果某个外部 skill 变成项目依赖，容易继续隐式依赖 `~/.codex/skills` 或 `~/.agents/skills`

这次整理把项目级 skill 明确成仓库资产，而不是个人机器上的隐式前置条件。

## 决策

`clawbar` 的 skill source of truth 固定为仓库内的 `.agents/skills/`。

规则如下：

- 项目自有 skill 直接维护在 `.agents/skills/<skill-name>/`
- 如果某个全局 skill 变成项目依赖，先登记到 `.agents/skills/registry.json`
- 外部 skill 需要 vendor 到仓库，而不是只存在于 `~/.codex/skills` 或 `~/.agents/skills`
- 项目文档、脚本和自动化默认只能依赖仓库内 skill

## 当前清单

清单定义在 `.agents/skills/registry.json`，当前已登记的项目自有 skill：

- `clawbar-dev-loop`
- `clawbar-menubar-screenshot`
- `clawbar-menubar-verify`

这些 skill 已按当前项目使用场景分类：

- `development`
- `visual-regression`
- `ui-verification`

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
