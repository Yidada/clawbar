# docs

项目内文档全部放在 `docs/`，用于记录当前仍然有效的开发流程、技能组织和验证策略。

## 当前文档

- `2026-04-03-testing-strategy.md`
  当前的自动化测试分层、统一 harness 入口、integration suite 约定、日志断言方式。
- `2026-04-04-project-skills-reorganization.md`
  项目级 skills 的 source of truth、registry 规则，以及与统一 harness 的关系。

## 约定

- 新文档统一放在 `docs/`
- 文件名统一使用 `YYYY-MM-DD-主题.md`
- 只保留当前仍然有效的流程说明；如果实现已经变了，优先更新原文档，不要继续堆“旧方案说明”
- 涉及命令入口时，优先记录 `python3 Tests/Harness/clawbarctl.py ...`，`Scripts/*.sh` 只作为兼容 wrapper 提及
