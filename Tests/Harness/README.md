# Clawbar Harness

`Tests/Harness/clawbarctl.py` is the single executable entrypoint for local app control, automated test flows, and diagnostics collection.

## Why it exists

- Give agents and developers one command surface instead of scattered shell scripts
- Keep every run legible by writing artifacts and `summary.json` files under `Artifacts/Harness/Runs/`
- Make logs first-class: smoke tests assert lifecycle events, integration suites keep per-suite logs, and diagnostics reuse the same layout

## Command groups

### `app`

```bash
python3 Tests/Harness/clawbarctl.py app start --mode menu-bar --restart
python3 Tests/Harness/clawbarctl.py app restart --mode ui
python3 Tests/Harness/clawbarctl.py app status
python3 Tests/Harness/clawbarctl.py app stop
python3 Tests/Harness/clawbarctl.py app dev-loop
```

`app start` and `app restart` accept:

- `--mode menu-bar|smoke|ui` to choose the launch surface
- `--env KEY=VALUE` for extra environment overrides
- `--openclaw-state missing|installed` plus `--openclaw-*` fixture flags to simulate installed or missing OpenClaw states during UI verification

### `test`

```bash
python3 Tests/Harness/clawbarctl.py test unit --coverage-gate
python3 Tests/Harness/clawbarctl.py test smoke
python3 Tests/Harness/clawbarctl.py test integration --suite all
python3 Tests/Harness/clawbarctl.py test integration --suite gateway
python3 Tests/Harness/clawbarctl.py test all
```

Available integration suites: `all`, `feishu`, `gateway`, `installer`, `provider`, `wechat`.

Useful flags:

- `test smoke --window-retries <n> --window-wait <seconds>`
- `test smoke --log-contains <pattern> --log-absent <pattern>`
- `test integration --log-contains <pattern> --log-absent <pattern>`

### `logs`

```bash
python3 Tests/Harness/clawbarctl.py logs collect
python3 Tests/Harness/clawbarctl.py logs assert --file <path> --contains "CLAWBAR_EVENT app.launch"
```

`logs collect` writes a diagnostics bundle. `logs assert` checks required or forbidden patterns in a specific log file.

## Artifact layout

- `Artifacts/Harness/Runs/<timestamp>-app-*` for app start, restart, stop, and status runs
- `Artifacts/Harness/Runs/<timestamp>-test-*` for unit, smoke, integration, and aggregate test flows
- `Artifacts/Harness/Runs/<timestamp>-logs-collect` for diagnostics bundles
- `Artifacts/Harness/State/app-state.json` for the currently tracked app process

Each run directory includes `summary.json`. Test runs also keep raw logs such as `swift-test.log`, `clawbar-smoke.log`, screenshots, or suite-specific XCTest logs.

## Compatibility

Top-level `Scripts/dev.sh`, `Scripts/check_coverage.sh`, `Scripts/smoke_test.sh`, and `Scripts/test.sh` remain as thin wrappers around the harness so older entrypoints still work, but new automation, docs, and skills should call the harness directly.
