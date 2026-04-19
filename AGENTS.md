# Repository Guidelines

## Project Structure & Module Organization
`clawbar` is a Swift Package Manager macOS menu bar companion for installing, configuring, and operating local Agent runtimes (OpenClaw, Hermes Agent). Shared app lifecycle and menu-state logic lives in `Sources/ClawbarKit`, while the app entry point, SwiftUI/AppKit integration, and per-runtime management flows (install, Gateway, providers, channels, TUI launch) live in `Sources/Clawbar`. The `AgentRuntime` protocol + capability sub-protocols (`AgentInstallable`, `AgentProviderCapable`, `AgentChannelCapable`, `AgentMessagingGatewayCapable`, `AgentTUILaunchable`) keep each runtime decoupled, with concrete adapters in `OpenClawRuntime.swift` and `HermesRuntime.swift`. Tests are in `Tests/ClawbarTests`, and the unified local control and test harness lives in `Tests/Harness`. Developer scripts are in `Scripts/`, release resources are in `Resources/Release`, packaging outputs are written to `dist/`, run artifacts are written to `Artifacts/`, release metadata lives in `version.env` and `CHANGELOG.md`, and design notes or investigation logs belong in `docs/` using names like `2026-04-03-menubar-ui-investigation.md`. Project-local skills live under `.agents/skills/`.

Machine-local signing material belongs under `.local/` inside the repo root when you need project-scoped secrets that must not be committed. Keep `.p12`, `.p8`, passwords, and generated secret files there, not in `docs/`, `Resources/Release/`, or tracked source directories.

`References/` is for committed, pinned upstream snapshots and design material that contributors or agents need locally for comparison. It is not the main codepath, and it is not a scratch space for temporary clones, worktrees, build outputs, or notes. When work touches OpenClaw-specific behavior, installation flow, protocol details, or API assumptions, inspect `References/openclaw` source code first and treat it as the primary reference for OpenClaw implementation details.

## OpenClaw Reference Workflow
For any task that depends on OpenClaw internals, prefer reading the upstream implementation under `References/openclaw` over relying on memory, screenshots, or stale notes. If the task depends on current OpenClaw interfaces, endpoint shapes, CLI flags, config formats, or other integration details that may have changed, refresh `References/openclaw` from the upstream source before implementing or documenting behavior.

Treat `References/openclaw` as a vendored snapshot, not as an active development target. Keep reference-sync updates separate from Clawbar behavior changes unless the task is explicitly about syncing the OpenClaw reference snapshot. Sync commits should clearly identify the upstream repo and pinned commit SHA they came from.

## Reference Management
`References/` should usually be committed when Clawbar depends on those files for integration work. Leaving critical reference material uncommitted makes agent behavior, code review, and future debugging non-reproducible across machines and CI.

Prefer this management order:

- Best current default: keep a committed snapshot under `References/<name>` and refresh it intentionally in a dedicated commit.
- If the reference becomes too large or churns too often: convert it to a pinned git submodule or another scripted sync mechanism.
- Avoid ad hoc nested clones or local-only worktrees inside the repo; they create ambiguous ownership and noisy diffs.

Keep transient material out of `References/`. Use `Artifacts/` for generated outputs, `docs/` for investigation notes, and local ignore rules for throwaway worktrees or caches.

## Documentation Entry Points
Keep the repository entrypoint docs aligned with the current command surface and project layout:

- `README.md` and `README.zh-CN.md` describe the product, common developer flows, and release entrypoints.
- `Tests/Harness/README.md` documents the `clawbarctl.py` command surface and artifact layout.
- `docs/README.md` indexes durable project docs under `docs/`.
- `AGENTS.md` captures repository-specific contributor and agent rules.
- `version.env` and `CHANGELOG.md` are the release source of truth for versioning and release notes.

When a change affects commands, packaging, test flows, or repo layout, update the relevant docs in the same change. Prefer editing the current canonical document over adding a second "new flow" note. Keep generated screenshots, logs, and diagnostics under `Artifacts/`, not in `docs/`.

## Build, Test, and Development Commands
Use the package root for all commands:

- `swift run Clawbar`: build and launch the menu bar app once.
- `swift build`: compile the package without running it.
- `swift test`: run the full XCTest suite directly.
- `python3 Tests/Harness/clawbarctl.py app dev-loop`: watch `Package.swift`, `Sources/`, and `Tests/`, then rebuild and relaunch automatically.
- `python3 Tests/Harness/clawbarctl.py app start --mode menu-bar|smoke|ui`: build and launch Clawbar in a tracked background session.
- `python3 Tests/Harness/clawbarctl.py app restart --mode menu-bar|smoke|ui`: restart Clawbar using the last known or provided mode.
- `python3 Tests/Harness/clawbarctl.py app status`: show the tracked app process state.
- `python3 Tests/Harness/clawbarctl.py app stop`: stop the tracked Clawbar process and any stale matching binaries.
- `python3 Tests/Harness/clawbarctl.py test unit --coverage-gate`: run tests with the `ClawbarKit` coverage gate.
- `python3 Tests/Harness/clawbarctl.py test smoke`: build, launch the smoke harness, capture a screenshot, and assert lifecycle logs.
- `python3 Tests/Harness/clawbarctl.py test integration --suite all`: run grouped XCTest suites for Feishu, WeChat, Provider, Gateway, Installer, and Hermes flows.
- `python3 Tests/Harness/clawbarctl.py test integration --suite hermes`: run only the Hermes Agent runtime suites (`AgentRuntimeRegistryTests`, `HermesInstallerTests`, `HermesProviderManagerTests`, `HermesGatewayManagerTests`, `HermesTUIManagerTests`).
- `python3 Tests/Harness/clawbarctl.py test all`: run unit + smoke + integration in one pass.
- `python3 Tests/Harness/clawbarctl.py logs collect`: collect the current diagnostics bundle.
- `python3 Tests/Harness/clawbarctl.py logs assert --file <path> --contains "..."`: assert required or forbidden log patterns in a recorded log file.
- `OUTPUT_FORMAT=dmg ./Scripts/package_app.sh`: build a local `.app` and `.dmg` under `dist/`.
- `./Scripts/sign_and_notarize.sh`: sign and notarize a local build after setting `SIGNING_IDENTITY` and the required Apple notary environment variables.
- `python3 Scripts/prepare_signing_assets.py --source-dir <path> --output-dir .local/signing ...`: normalize local signing exports into ignored project-local files for `sign_and_notarize.sh` and GitHub Environment setup.
- `bash Scripts/validate_release_metadata.sh`: validate `version.env` and, optionally, a release tag.
- `bash Scripts/validate_changelog.sh <version>`: require a finalized top changelog section for a release version.
- `bash Scripts/extract_release_notes.sh <version>`: print the release notes body for the requested version from `CHANGELOG.md`.
- `bash Scripts/check-release-assets.sh [version|tag]`: assert the expected versioned DMG exists under `dist/`.

Compatibility note:

- `./Scripts/dev.sh`, `./Scripts/check_coverage.sh`, `./Scripts/smoke_test.sh`, and `./Scripts/test.sh` remain available as thin wrappers around `Tests/Harness/clawbarctl.py`.
- `Scripts/package_app.sh` and `Scripts/sign_and_notarize.sh` are the canonical local packaging entrypoints and write artifacts under `dist/`.
- Official releases are version/changelog-driven: `v<version>` tags must match `version.env`, and `CHANGELOG.md` must contain the finalized top section for that version.
- Harness artifacts live under `Artifacts/Harness/Runs/<timestamp>-<label>/`, with the currently tracked app state stored at `Artifacts/Harness/State/app-state.json`.

## Coding Style & Naming Conventions
Follow the existing Swift style: 4-space indentation, one top-level type per file where practical, `UpperCamelCase` for types, `lowerCamelCase` for properties and methods, and clear scene/view names such as `ApplicationManagementView`. Keep UI code thin in `Sources/Clawbar` and push testable logic into `ClawbarKit`. The package enables Swift strict concurrency features, so prefer `Sendable` types and concurrency-safe APIs when adding shared state.

## Testing Guidelines
Tests use `XCTest`. Name test files after the subject under test, for example `AppConfigurationTests.swift`, and use descriptive methods like `testIsSmokeTestEnabledReturnsTrueWhenFlagIsSet`. Add or update unit tests for logic changes in `ClawbarKit`. For menu or window behavior, run `python3 Tests/Harness/clawbarctl.py test smoke`; UI changes should keep the smoke harness passing and refresh screenshot evidence when relevant. When a change affects Feishu, WeChat, Provider, Gateway, Installer, or Hermes flows, rerun the matching `python3 Tests/Harness/clawbarctl.py test integration --suite ...` group.

## Commit & Pull Request Guidelines
Recent history uses short, imperative commit subjects such as `Add OpenClaw install flow and status to Clawbar menu`. Keep commits focused and descriptive. Pull requests should summarize behavior changes, list validation commands run, link the related issue when applicable, and include screenshots for menu/window UI changes. Avoid mixing reference-material updates in `References/` with app changes unless the PR is explicitly about syncing references.

## Project Skills
Treat project-local `.agents/skills/` as the source of truth for this repository. Do not assume `~/.codex/skills` or `~/.agents/skills` exists on another machine. Register every repo-relevant skill in `.agents/skills/registry.json`, keep project-owned skills in-tree, and vendor any external skill into `.agents/skills/<name>` before relying on it in docs or automation. Use `python3 Scripts/project_skills.py list`, `check`, and `sync` to manage the local skill inventory. When Clawbar or OpenClaw behavior is broken or unclear, use the project-local `clawbar-openclaw-logs` skill first to collect the active runtime logs before guessing at root cause.

## JavaScript REPL (Node)
- Use `js_repl` for Node-backed JavaScript with top-level await in a persistent kernel.
- `js_repl` is a freeform/custom tool. Direct `js_repl` calls must send raw JavaScript tool input (optionally with first-line `// codex-js-repl: timeout_ms=15000`). Do not wrap code in JSON (for example `{"code":"..."}`), quotes, or markdown code fences.
- Helpers: `codex.cwd`, `codex.homeDir`, `codex.tmpDir`, `codex.tool(name, args?)`, and `codex.emitImage(imageLike)`.
- `codex.tool` executes a normal tool call and resolves to the raw tool output object. Use it for shell and non-shell tools alike. Nested tool outputs stay inside JavaScript unless you emit them explicitly.
- `codex.emitImage(...)` adds one image to the outer `js_repl` function output each time you call it, so you can call it multiple times to emit multiple images. It accepts a data URL, a single `input_image` item, an object like `{ bytes, mimeType }`, or a raw tool response object with exactly one image and no text. It rejects mixed text-and-image content.
- `codex.tool(...)` and `codex.emitImage(...)` keep stable helper identities across cells. Saved references and persisted objects can reuse them in later cells, but async callbacks that fire after a cell finishes still fail because no exec is active.
- Request full-resolution image processing with `detail: "original"` only when the `view_image` tool schema includes a `detail` argument. The same availability applies to `codex.emitImage(...)`: if `view_image.detail` is present, you may also pass `detail: "original"` there. Use this when high-fidelity image perception or precise localization is needed, especially for CUA agents.
- Example of sharing an in-memory Playwright screenshot: `await codex.emitImage({ bytes: await page.screenshot({ type: "jpeg", quality: 85 }), mimeType: "image/jpeg", detail: "original" })`.
- Example of sharing a local image tool result: `await codex.emitImage(codex.tool("view_image", { path: "/absolute/path", detail: "original" }))`.
- When encoding an image to send with `codex.emitImage(...)` or `view_image`, prefer JPEG at about 85 quality when lossy compression is acceptable; use PNG when transparency or lossless detail matters. Smaller uploads are faster and less likely to hit size limits.
- Top-level bindings persist across cells. If a cell throws, prior bindings remain available and bindings that finished initializing before the throw often remain usable in later cells. For code you plan to reuse across cells, prefer declaring or assigning it in direct top-level statements before operations that might throw. If you hit `SyntaxError: Identifier 'x' has already been declared`, first reuse the existing binding, reassign a previously declared `let`, or pick a new descriptive name. Use `{ ... }` only for a short temporary block when you specifically need local scratch names; do not wrap an entire cell in block scope if you want those names reusable later. Reset the kernel with `js_repl_reset` only when you need a clean state.
- Top-level static import declarations (for example `import x from "./file.js"`) are currently unsupported in `js_repl`; use dynamic imports with `await import("pkg")`, `await import("./file.js")`, or `await import("/abs/path/file.mjs")` instead. Imported local files must be ESM `.js`/`.mjs` files and run in the same REPL VM context. Bare package imports always resolve from REPL-global search roots (`CODEX_JS_REPL_NODE_MODULE_DIRS`, then cwd), not relative to the imported file location. Local files may statically import only other local relative/absolute/`file://` `.js`/`.mjs` files; package and builtin imports from local files must stay dynamic. `import.meta.resolve()` returns importable strings such as `file://...`, bare package names, and `node:...` specifiers. Local file modules reload between execs, while top-level bindings persist until `js_repl_reset`.
- Avoid direct access to `process.stdout` / `process.stderr` / `process.stdin`; it can corrupt the JSON line protocol. Use `console.log`, `codex.tool(...)`, and `codex.emitImage(...)`.
