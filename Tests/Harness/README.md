# Clawbar Harness

`Tests/Harness/clawbarctl.py` is the single executable entrypoint for local app control, test runs, and diagnostics collection.

## Why it exists

- Give agents and developers one command surface instead of scattered shell scripts.
- Keep every run legible by writing artifacts and `summary.json` files under `Artifacts/Harness/Runs/`.
- Make logs first-class: smoke tests assert lifecycle events, integration suites keep per-suite logs, and diagnostics reuse the same layout.

## Common commands

```bash
python3 Tests/Harness/clawbarctl.py app dev-loop
python3 Tests/Harness/clawbarctl.py app start --mode ui --restart --openclaw-state installed
python3 Tests/Harness/clawbarctl.py app stop
python3 Tests/Harness/clawbarctl.py test unit --coverage-gate
python3 Tests/Harness/clawbarctl.py test smoke
python3 Tests/Harness/clawbarctl.py test integration --suite all
python3 Tests/Harness/clawbarctl.py test all
python3 Tests/Harness/clawbarctl.py logs collect
python3 Tests/Harness/clawbarctl.py logs assert --file <path> --contains "CLAWBAR_EVENT app.launch"
```

## Artifact layout

- `Artifacts/Harness/Runs/<timestamp>-app-*` for app start/stop/status runs
- `Artifacts/Harness/Runs/<timestamp>-test-*` for unit, smoke, integration, and aggregate test flows
- `Artifacts/Harness/Runs/<timestamp>-logs-collect` for diagnostics bundles
- `Artifacts/Harness/State/app-state.json` for the currently tracked app process

Each run directory includes `summary.json`. Test runs also keep raw logs such as `swift-test.log`, `clawbar-smoke.log`, or suite-specific logs.

## Compatibility

Top-level `Scripts/*.sh` commands remain as thin wrappers around the harness so older entrypoints still work, but new automation and skill docs should call the harness directly.
