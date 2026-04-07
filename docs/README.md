# docs

`docs/` 用来保存当前仓库仍然有效的流程说明、发布文档和调查记录，不是临时草稿或产物目录。

## 相关入口

- `README.md` / `README.zh-CN.md`
  面向使用者和开发者的仓库总览、常用工作流和发布入口。
- `AGENTS.md`
  仓库级协作约定、命令入口、参考快照规则和文档同步要求。
- `Tests/Harness/README.md`
  `clawbarctl.py` 的命令面、产物布局和兼容性说明。

## 当前文档

- `2026-04-03-testing-strategy.md`
  当前的自动化测试分层、统一 harness 入口、integration suite 约定和日志断言方式。
- `2026-04-04-project-skills-reorganization.md`
  项目级 skills 的 source of truth、registry 规则，以及与统一 harness 的关系。
- `2026-04-05-notarized-release-process.md`
  正式 macOS 发布所需的签名、notarization、DMG 流程，以及必须准备的 GitHub secrets。
- `2026-04-06-local-signing-guide.md`
  面向本地开发者的详细签名与 notarization 操作指引，包括证书准备、API key、脚本用法和常见故障排查。
- `2026-04-07-main-branch-packaging-setup.md`
  说明哪些签名配置可以保存在项目内但必须被 Git 忽略，以及如何把同一套 secrets 安全接到 `main` 自动打包和 tag release workflow。

## 文档约定

- 新文档统一放在 `docs/`
- 文件名统一使用 `YYYY-MM-DD-主题.md`
- 实现、命令入口或发布流程变化时，优先更新现有文档，不要继续堆“旧方案说明”
- 涉及命令入口时，优先记录 `python3 Tests/Harness/clawbarctl.py ...`；`Scripts/*.sh` 只作为兼容 wrapper 或打包脚本补充说明
- 变更如果影响仓库入口说明，要同时同步 `README.md`、`README.zh-CN.md`、`AGENTS.md` 或 `Tests/Harness/README.md`
- OpenClaw 内部实现、CLI 参数、协议细节优先以 `References/openclaw/` 为准，不要把上游源码快照塞进 `docs/`
- 截图、日志、诊断包、构建产物放到 `Artifacts/`，不要提交到 `docs/`
