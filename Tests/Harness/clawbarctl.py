#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import shlex
import shutil
import signal
import subprocess
import sys
import textwrap
import time
from dataclasses import dataclass
from typing import Any


DEFAULT_OPENCLAW_BINARY_PATH = "/opt/homebrew/bin/openclaw"
DEFAULT_OPENCLAW_DETAIL = "Provider 已配置 · Gateway 可达 · Channel 已就绪"
DEFAULT_OPENCLAW_EXCERPT = "OpenClaw 2026.4.2"
SMOKE_LOG_PATTERNS = [
    "CLAWBAR_EVENT app.launch",
    "mode=smokeTest",
    "CLAWBAR_EVENT smoke.window.shown",
]
INTEGRATION_SUITES: dict[str, list[str]] = {
    "feishu": ["OpenClawFeishuChannelManagerTests"],
    "wechat": ["OpenClawChannelManagerTests"],
    "provider": ["OpenClawProviderManagerTests"],
    "gateway": [
        "OpenClawGatewayManagerTests",
        "OpenClawGatewayCredentialStoreTests",
        "OpenClawTUIManagerTests",
    ],
    "installer": ["OpenClawInstallerTests"],
    "hermes": [
        "AgentRuntimeRegistryTests",
        "HermesInstallerTests",
        "HermesProviderManagerTests",
        "HermesGatewayManagerTests",
        "HermesTUIManagerTests",
    ],
}


class CommandFailure(RuntimeError):
    pass


@dataclass
class CommandResult:
    command: list[str]
    exit_code: int
    stdout: str
    stderr: str
    combined: str


def find_repo_root(start: pathlib.Path) -> pathlib.Path:
    current = start.resolve()
    for candidate in [current, *current.parents]:
        if (candidate / "Package.swift").is_file() and (candidate / "Sources").is_dir():
            return candidate
    raise CommandFailure(f"Unable to locate repository root from {start}")


SCRIPT_PATH = pathlib.Path(__file__).resolve()
ROOT_DIR = find_repo_root(SCRIPT_PATH)
ARTIFACTS_ROOT = ROOT_DIR / "Artifacts" / "Harness"
RUNS_ROOT = ARTIFACTS_ROOT / "Runs"
STATE_ROOT = ARTIFACTS_ROOT / "State"
APP_STATE_PATH = STATE_ROOT / "app-state.json"


def timestamp_slug() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")


def ensure_directory(path: pathlib.Path) -> pathlib.Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def create_run_directory(label: str) -> pathlib.Path:
    run_dir = ensure_directory(RUNS_ROOT) / f"{timestamp_slug()}-{label}"
    run_dir.mkdir(parents=True, exist_ok=False)
    return run_dir


def relative_to_root(path: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT_DIR))
    except ValueError:
        return str(path.resolve())


def shell_join(parts: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in parts)


def write_summary(run_dir: pathlib.Path, payload: dict[str, Any]) -> pathlib.Path:
    summary_path = run_dir / "summary.json"
    summary_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary_path


def print_run_result(label: str, run_dir: pathlib.Path, summary_path: pathlib.Path, extra: list[str] | None = None) -> None:
    print(f"{label}: ok")
    print(f"artifact_dir: {run_dir}")
    print(f"summary_json: {summary_path}")
    if extra:
        for line in extra:
            print(line)


def load_app_state() -> dict[str, Any] | None:
    if not APP_STATE_PATH.is_file():
        return None
    return json.loads(APP_STATE_PATH.read_text(encoding="utf-8"))


def save_app_state(payload: dict[str, Any]) -> None:
    ensure_directory(STATE_ROOT)
    APP_STATE_PATH.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def clear_app_state() -> None:
    if APP_STATE_PATH.exists():
        APP_STATE_PATH.unlink()


def build_environment(overrides: dict[str, str] | None = None) -> dict[str, str]:
    env = dict(os.environ)
    if overrides:
        env.update(overrides)
    return env


def command_output(
    command: list[str],
    *,
    cwd: pathlib.Path = ROOT_DIR,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> CommandResult:
    completed = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        capture_output=True,
    )
    combined = completed.stdout + completed.stderr
    result = CommandResult(
        command=command,
        exit_code=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
        combined=combined,
    )
    if check and completed.returncode != 0:
        raise CommandFailure(
            f"Command failed ({completed.returncode}): {shell_join(command)}\n{combined.strip()}"
        )
    return result


def stream_command(
    command: list[str],
    *,
    log_path: pathlib.Path,
    cwd: pathlib.Path = ROOT_DIR,
    env: dict[str, str] | None = None,
) -> int:
    with log_path.open("w", encoding="utf-8") as handle:
        handle.write(f"$ {shell_join(command)}\n\n")
        handle.flush()
        process = subprocess.run(
            command,
            cwd=cwd,
            env=env,
            text=True,
            stdout=handle,
            stderr=subprocess.STDOUT,
        )
    return process.returncode


def append_text(path: pathlib.Path, text: str) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(text)


def build_binary(run_dir: pathlib.Path | None = None) -> pathlib.Path:
    log_path = (run_dir / "swift-build.log") if run_dir else None
    command = ["swift", "build"]
    if log_path:
        exit_code = stream_command(command, log_path=log_path)
        if exit_code != 0:
            raise CommandFailure(f"swift build failed; inspect {log_path}")
    else:
        command_output(command)

    result = command_output(["swift", "build", "--show-bin-path"])
    bin_dir = pathlib.Path(result.stdout.strip())
    binary_path = (bin_dir / "Clawbar").resolve()
    if not binary_path.is_file():
        raise CommandFailure(f"Expected built Clawbar binary at {binary_path}")
    return binary_path


def resolve_existing_binary() -> pathlib.Path:
    result = command_output(["swift", "build", "--show-bin-path"])
    bin_dir = pathlib.Path(result.stdout.strip())
    binary_path = (bin_dir / "Clawbar").resolve()
    if not binary_path.is_file():
        raise CommandFailure(
            f"Expected built Clawbar binary at {binary_path}. Run `swift build` or omit --no-build."
        )
    return binary_path


def running_pid(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def matching_pids(binary_path: str) -> list[int]:
    result = command_output(["pgrep", "-f", binary_path], check=False)
    if result.exit_code != 0:
        return []
    pids: list[int] = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            pids.append(int(line))
        except ValueError:
            continue
    return pids


def terminate_pid(pid: int, *, include_group: bool = False, timeout: float = 4.0) -> None:
    targets: list[tuple[int, bool]] = []
    if include_group:
        try:
            pgid = os.getpgid(pid)
            if pgid > 0:
                targets.append((pgid, True))
        except ProcessLookupError:
            return
    targets.append((pid, False))

    for target, is_group in targets:
        try:
            if is_group:
                os.killpg(target, signal.SIGTERM)
            else:
                os.kill(target, signal.SIGTERM)
        except ProcessLookupError:
            continue

    deadline = time.time() + timeout
    while time.time() < deadline and running_pid(pid):
        time.sleep(0.2)

    if running_pid(pid):
        for target, is_group in targets:
            try:
                if is_group:
                    os.killpg(target, signal.SIGKILL)
                else:
                    os.kill(target, signal.SIGKILL)
            except ProcessLookupError:
                continue


def stop_existing_app(binary_path: str | None = None) -> list[int]:
    stopped: list[int] = []
    state = load_app_state()
    tracked_binary = binary_path or (state or {}).get("binary_path")

    if state and running_pid(int(state.get("pid", 0))):
        pid = int(state["pid"])
        terminate_pid(pid, include_group=True)
        stopped.append(pid)

    if tracked_binary:
        for pid in matching_pids(tracked_binary):
            if pid == os.getpid() or pid in stopped:
                continue
            terminate_pid(pid)
            stopped.append(pid)

    clear_app_state()
    return stopped


def parse_key_values(items: list[str] | None) -> dict[str, str]:
    parsed: dict[str, str] = {}
    for item in items or []:
        if "=" not in item:
            raise CommandFailure(f"Expected KEY=VALUE format, got: {item}")
        key, value = item.split("=", 1)
        key = key.strip()
        if not key:
            raise CommandFailure(f"Expected non-empty env key in: {item}")
        parsed[key] = value
    return parsed


def make_app_environment(args: argparse.Namespace) -> dict[str, str]:
    overrides: dict[str, str] = parse_key_values(getattr(args, "env", None))

    if args.mode == "smoke":
        overrides["CLAWBAR_SMOKE_TEST"] = "1"
        overrides.pop("CLAWBAR_UI_TEST", None)
    elif args.mode == "ui":
        overrides["CLAWBAR_UI_TEST"] = "1"
        overrides.pop("CLAWBAR_SMOKE_TEST", None)
    else:
        overrides.pop("CLAWBAR_SMOKE_TEST", None)
        overrides.pop("CLAWBAR_UI_TEST", None)

    if args.openclaw_state:
        overrides["CLAWBAR_TEST_OPENCLAW_STATE"] = args.openclaw_state
        if args.openclaw_binary_path:
            overrides["CLAWBAR_TEST_OPENCLAW_BINARY_PATH"] = args.openclaw_binary_path
        if args.openclaw_title:
            overrides["CLAWBAR_TEST_OPENCLAW_TITLE"] = args.openclaw_title
        if args.openclaw_detail:
            overrides["CLAWBAR_TEST_OPENCLAW_DETAIL"] = args.openclaw_detail
        if args.openclaw_excerpt:
            overrides["CLAWBAR_TEST_OPENCLAW_EXCERPT"] = args.openclaw_excerpt

    return build_environment(overrides)


def launch_app_process(
    *,
    binary_path: pathlib.Path,
    log_path: pathlib.Path,
    env: dict[str, str],
) -> subprocess.Popen[str]:
    handle = log_path.open("w", encoding="utf-8")
    handle.write(f"$ {binary_path}\n\n")
    handle.flush()
    process = subprocess.Popen(
        [str(binary_path)],
        cwd=ROOT_DIR,
        env=env,
        stdout=handle,
        stderr=subprocess.STDOUT,
        start_new_session=True,
        text=True,
    )
    handle.close()
    return process


def start_app_command(args: argparse.Namespace) -> int:
    run_dir = create_run_directory(f"app-{args.mode}")
    binary_path = build_binary(run_dir) if args.build else resolve_existing_binary()
    if args.restart:
        stop_existing_app(str(binary_path))

    log_path = run_dir / "clawbar.log"
    env = make_app_environment(args)
    process = launch_app_process(binary_path=binary_path, log_path=log_path, env=env)

    time.sleep(args.wait_seconds)
    if process.poll() is not None:
        raise CommandFailure(
            f"Clawbar exited early with code {process.returncode}; inspect {log_path}"
        )

    state = {
        "version": 1,
        "pid": process.pid,
        "binary_path": str(binary_path),
        "log_path": str(log_path),
        "run_dir": str(run_dir),
        "mode": args.mode,
        "started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "env_overrides": {
            key: value
            for key, value in env.items()
            if os.environ.get(key) != value
        },
    }
    save_app_state(state)

    summary = {
        "command": "app start",
        "status": "ok",
        "mode": args.mode,
        "pid": process.pid,
        "binary_path": str(binary_path),
        "log_path": str(log_path),
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result(
        "app.start",
        run_dir,
        summary_path,
        extra=[
            f"pid: {process.pid}",
            f"log_path: {log_path}",
        ],
    )
    return 0


def stop_app_command(args: argparse.Namespace) -> int:
    state = load_app_state()
    binary_path = args.binary_path or ((state or {}).get("binary_path"))
    stopped = stop_existing_app(binary_path)
    run_dir = create_run_directory("app-stop")
    summary = {
        "command": "app stop",
        "status": "ok",
        "stopped_pids": stopped,
        "binary_path": binary_path,
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result(
        "app.stop",
        run_dir,
        summary_path,
        extra=[f"stopped_pids: {stopped or '[]'}"],
    )
    return 0


def restart_app_command(args: argparse.Namespace) -> int:
    state = load_app_state()
    if state and not any(
        [
            args.mode,
            args.openclaw_state,
            args.openclaw_binary_path,
            args.openclaw_title,
            args.openclaw_detail,
            args.openclaw_excerpt,
            args.env,
        ]
    ):
        args.mode = state.get("mode", "menu-bar")
        restored = state.get("env_overrides", {})
        args.env = [f"{key}={value}" for key, value in restored.items()]

    args.restart = True
    if not args.mode:
        args.mode = "menu-bar"
    return start_app_command(args)


def status_app_command(_: argparse.Namespace) -> int:
    run_dir = create_run_directory("app-status")
    state = load_app_state()
    if not state:
        summary = {"command": "app status", "status": "stopped"}
        summary_path = write_summary(run_dir, summary)
        print_run_result("app.status", run_dir, summary_path, extra=["state: stopped"])
        return 0

    pid = int(state.get("pid", 0))
    status = "running" if running_pid(pid) else "stale"
    summary = {"command": "app status", "status": status, "state": state}
    summary_path = write_summary(run_dir, summary)
    print_run_result(
        "app.status",
        run_dir,
        summary_path,
        extra=[
            f"state: {status}",
            f"pid: {pid}",
            f"log_path: {state.get('log_path')}",
        ],
    )
    return 0


def watch_fingerprint() -> str:
    entries: list[str] = []
    for relative in ["Package.swift", "Sources", "Tests"]:
        target = ROOT_DIR / relative
        if target.is_file():
            stat = target.stat()
            entries.append(f"{relative}:{stat.st_mtime_ns}:{stat.st_size}")
            continue
        if not target.is_dir():
            continue
        for path in sorted(
            candidate for candidate in target.rglob("*") if candidate.is_file() and not any(part.startswith(".") for part in candidate.parts)
        ):
            stat = path.stat()
            entries.append(f"{path.relative_to(ROOT_DIR)}:{stat.st_mtime_ns}:{stat.st_size}")
    return hashlib.sha256("\n".join(entries).encode("utf-8")).hexdigest()


def dev_loop_command(args: argparse.Namespace) -> int:
    run_dir = create_run_directory("app-dev-loop")
    runner_log = run_dir / "dev-loop.log"
    binary_path = build_binary(run_dir)
    app_log_path = run_dir / "clawbar.log"

    def log_line(message: str) -> None:
        line = f"[{dt.datetime.now().strftime('%H:%M:%S')}] {message}\n"
        sys.stdout.write(line)
        sys.stdout.flush()
        append_text(runner_log, line)

    append_text(runner_log, f"repo_root={ROOT_DIR}\n")
    append_text(runner_log, f"app_log={app_log_path}\n")
    stop_existing_app(str(binary_path))

    last_fingerprint = ""
    active_pid: int | None = None

    def launch() -> int:
        env = build_environment()
        process = launch_app_process(binary_path=binary_path, log_path=app_log_path, env=env)
        save_app_state(
            {
                "version": 1,
                "pid": process.pid,
                "binary_path": str(binary_path),
                "log_path": str(app_log_path),
                "run_dir": str(run_dir),
                "mode": "menu-bar",
                "started_at": dt.datetime.now(dt.timezone.utc).isoformat(),
                "env_overrides": {},
            }
        )
        return process.pid

    log_line(f"Watching for changes every {args.poll_interval:.1f}s")
    log_line(f"Runner log: {runner_log}")
    log_line(f"App log: {app_log_path}")

    try:
        while True:
            current = watch_fingerprint()
            if current != last_fingerprint:
                log_line("change detected, building...")
                binary_path_local = build_binary(run_dir)
                if active_pid and running_pid(active_pid):
                    terminate_pid(active_pid, include_group=True)
                active_pid = launch()
                log_line(f"app restarted (pid={active_pid})")
                last_fingerprint = current
                binary_path = binary_path_local
            elif active_pid and not running_pid(active_pid):
                log_line("app missing, relaunching...")
                active_pid = launch()
                log_line(f"app restarted (pid={active_pid})")
            time.sleep(max(args.poll_interval, 0.2))
    except KeyboardInterrupt:
        log_line("received interrupt, stopping dev loop")
    finally:
        stop_existing_app(str(binary_path))

    summary = {
        "command": "app dev-loop",
        "status": "ok",
        "runner_log": str(runner_log),
        "app_log": str(app_log_path),
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result("app.dev-loop", run_dir, summary_path)
    return 0


def assert_log_patterns(text: str, *, contains: list[str], absent: list[str]) -> list[str]:
    failures: list[str] = []
    for pattern in contains:
        if pattern not in text:
            failures.append(f"missing required log pattern: {pattern}")
    for pattern in absent:
        if pattern in text:
            failures.append(f"unexpected log pattern present: {pattern}")
    return failures


def assert_log_file(path: pathlib.Path, *, contains: list[str], absent: list[str]) -> None:
    if not path.is_file():
        raise CommandFailure(f"Log file not found: {path}")
    text = path.read_text(encoding="utf-8", errors="replace")
    failures = assert_log_patterns(text, contains=contains, absent=absent)
    if failures:
        raise CommandFailure("\n".join(failures))


def coverage_gate(run_dir: pathlib.Path) -> dict[str, Any]:
    result = command_output(["swift", "test", "--show-codecov-path"])
    codecov_path = pathlib.Path(result.stdout.strip())
    payload = json.loads(codecov_path.read_text(encoding="utf-8"))
    target_root = str((ROOT_DIR / "Sources" / "ClawbarKit").resolve())
    functions = payload["data"][0]["functions"]
    target_functions = [
        function
        for function in functions
        if any(filename.startswith(target_root) for filename in function["filenames"])
    ]
    if not target_functions:
        raise CommandFailure(f"No functions found under {target_root}")
    uncovered = [function for function in target_functions if function["count"] == 0]
    report = {
        "covered": len(target_functions) - len(uncovered),
        "total": len(target_functions),
        "uncovered": [
            {"name": function["name"], "file": function["filenames"][0]}
            for function in uncovered
        ],
    }
    (run_dir / "coverage-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    if uncovered:
        lines = "\n".join(
            f"- {item['name']} [{item['file']}]" for item in report["uncovered"]
        )
        raise CommandFailure(
            f"ClawbarKit function coverage gate failed ({report['covered']}/{report['total']})\n{lines}"
        )
    return report


def unit_test_command(args: argparse.Namespace) -> int:
    run_dir = create_run_directory("test-unit")
    log_path = run_dir / "swift-test.log"
    command = ["swift", "test"]
    if args.coverage_gate:
        command.append("--enable-code-coverage")
    if args.filter:
        command.extend(["--filter", args.filter])

    exit_code = stream_command(command, log_path=log_path)
    if exit_code != 0:
        raise CommandFailure(f"swift test failed; inspect {log_path}")

    assert_log_file(
        log_path,
        contains=args.log_contains or [],
        absent=args.log_absent or [],
    )

    coverage_report = coverage_gate(run_dir) if args.coverage_gate else None
    summary = {
        "command": "test unit",
        "status": "ok",
        "log_path": str(log_path),
        "coverage_gate": coverage_report,
    }
    summary_path = write_summary(run_dir, summary)
    extra = [f"log_path: {log_path}"]
    if coverage_report:
        extra.append(
            f"coverage: {coverage_report['covered']}/{coverage_report['total']} functions in Sources/ClawbarKit"
        )
    print_run_result("test.unit", run_dir, summary_path, extra=extra)
    return 0


def find_smoke_window() -> dict[str, Any] | None:
    result = command_output(
        [
            "swift",
            "-e",
            textwrap.dedent(
                """
                import CoreGraphics
                import Foundation

                let expectedOwner = "Clawbar"
                let expectedTitle = "Clawbar Smoke Test"
                let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

                let exactMatch = windows.first(where: { window in
                    let owner = window[kCGWindowOwnerName as String] as? String
                    let title = window[kCGWindowName as String] as? String
                    return owner == expectedOwner && title == expectedTitle
                })

                let fallbackMatch = windows.first(where: { window in
                    let owner = window[kCGWindowOwnerName as String] as? String
                    return owner == expectedOwner
                })

                if let match = exactMatch ?? fallbackMatch,
                   let id = match[kCGWindowNumber as String] as? NSNumber,
                   let bounds = match[kCGWindowBounds as String] as? [String: Any],
                   let x = bounds["X"] as? NSNumber,
                   let y = bounds["Y"] as? NSNumber,
                   let width = bounds["Width"] as? NSNumber,
                   let height = bounds["Height"] as? NSNumber {
                    let payload: [String: Any] = [
                        "id": id.intValue,
                        "x": x.intValue,
                        "y": y.intValue,
                        "width": width.intValue,
                        "height": height.intValue,
                    ]
                    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
                    print(String(decoding: data, as: UTF8.self))
                }
                """
            ),
        ],
        check=False,
    )
    output = result.stdout.strip()
    if not output:
        return None
    return json.loads(output)


def smoke_test_command(args: argparse.Namespace) -> int:
    run_dir = create_run_directory("test-smoke")
    binary_path = build_binary(run_dir)
    stop_existing_app(str(binary_path))

    log_path = run_dir / "clawbar-smoke.log"
    screenshot_path = run_dir / "hello-world-smoke.png"
    env = build_environment({"CLAWBAR_SMOKE_TEST": "1"})
    process = launch_app_process(binary_path=binary_path, log_path=log_path, env=env)

    try:
        window_info: dict[str, Any] | None = None
        for _ in range(args.window_retries):
            window_info = find_smoke_window()
            if window_info:
                break
            if process.poll() is not None:
                raise CommandFailure(
                    f"Clawbar exited early with code {process.returncode}; inspect {log_path}"
                )
            time.sleep(args.window_wait)

        if not window_info:
            raise CommandFailure(f"Smoke test window was not found; inspect {log_path}")

        window_id = str(window_info["id"])
        capture = command_output(
            ["screencapture", "-x", "-l", window_id, str(screenshot_path)],
            check=False,
        )
        if capture.exit_code != 0:
            region = "{x},{y},{width},{height}".format(**window_info)
            capture = command_output(
                ["screencapture", "-x", "-R", region, str(screenshot_path)],
                check=False,
            )
        if capture.exit_code != 0:
            raise CommandFailure(
                f"Smoke screenshot failed; inspect {log_path}\n{capture.combined.strip()}"
            )
        if not screenshot_path.is_file() or screenshot_path.stat().st_size == 0:
            raise CommandFailure(f"Screenshot was not created: {screenshot_path}")

        contains = SMOKE_LOG_PATTERNS + (args.log_contains or [])
        assert_log_file(log_path, contains=contains, absent=args.log_absent or [])
    finally:
        stop_existing_app(str(binary_path))

    summary = {
        "command": "test smoke",
        "status": "ok",
        "log_path": str(log_path),
        "screenshot_path": str(screenshot_path),
        "window_id": window_id,
        "window_bounds": window_info,
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result(
        "test.smoke",
        run_dir,
        summary_path,
        extra=[
            f"log_path: {log_path}",
            f"screenshot_path: {screenshot_path}",
        ],
    )
    return 0


def selected_integration_filters(suites: list[str]) -> list[str]:
    filters: list[str] = []
    expanded = set(suites)
    if "all" in expanded:
        expanded = set(INTEGRATION_SUITES.keys())
    for suite in sorted(expanded):
        if suite not in INTEGRATION_SUITES:
            raise CommandFailure(f"Unknown integration suite: {suite}")
        filters.extend(INTEGRATION_SUITES[suite])
    return filters


def integration_test_command(args: argparse.Namespace) -> int:
    run_dir = create_run_directory("test-integration")
    suites = args.suite or ["all"]
    filters = selected_integration_filters(suites)
    logs: list[dict[str, Any]] = []

    for test_filter in filters:
        safe_name = test_filter.replace("/", "-")
        log_path = run_dir / f"{safe_name}.log"
        command = ["swift", "test", "--filter", test_filter]
        exit_code = stream_command(command, log_path=log_path)
        if exit_code != 0:
            raise CommandFailure(f"integration suite failed ({test_filter}); inspect {log_path}")
        assert_log_file(
            log_path,
            contains=args.log_contains or [],
            absent=args.log_absent or [],
        )
        logs.append({"filter": test_filter, "log_path": str(log_path)})

    summary = {
        "command": "test integration",
        "status": "ok",
        "suites": suites,
        "runs": logs,
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result(
        "test.integration",
        run_dir,
        summary_path,
        extra=[f"suites: {', '.join(suites)}"],
    )
    return 0


def all_test_command(args: argparse.Namespace) -> int:
    unit_args = argparse.Namespace(
        coverage_gate=True,
        filter=None,
        log_contains=[],
        log_absent=[],
    )
    smoke_args = argparse.Namespace(
        window_retries=40,
        window_wait=0.5,
        log_contains=[],
        log_absent=[],
    )
    integration_args = argparse.Namespace(
        suite=["all"],
        log_contains=[],
        log_absent=[],
    )
    unit_test_command(unit_args)
    smoke_test_command(smoke_args)
    integration_test_command(integration_args)

    run_dir = create_run_directory("test-all")
    summary = {
        "command": "test all",
        "status": "ok",
        "includes": ["unit (coverage gate)", "smoke", "integration (all suites)"],
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result("test.all", run_dir, summary_path)
    return 0


def tail_to_file(source: pathlib.Path, destination: pathlib.Path, lines: int = 200) -> bool:
    if not source.is_file():
        return False
    content = source.read_text(encoding="utf-8", errors="replace").splitlines()
    destination.write_text("\n".join(content[-lines:]) + ("\n" if content else ""), encoding="utf-8")
    return True


def copy_any(source: pathlib.Path, destination: pathlib.Path) -> bool:
    if not source.exists():
        return False
    if source.is_dir():
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(source, destination)
    else:
        ensure_directory(destination.parent)
        shutil.copy2(source, destination)
    return True


def collect_logs_command(args: argparse.Namespace) -> int:
    run_dir = create_run_directory("logs-collect")
    summary_lines = [
        "Clawbar diagnostics",
        f"generated_at: {dt.datetime.now().isoformat()}",
        f"repo_root: {ROOT_DIR}",
        f"artifact_dir: {run_dir}",
        "",
    ]

    def note(section: str, message: str) -> None:
        summary_lines.append(f"[{section}] {message}")

    processes = command_output(["ps", "aux"], check=False)
    process_lines = [
        line for line in processes.stdout.splitlines()
        if any(token in line for token in ["Clawbar", "openclaw", "QClaw"])
    ]
    (run_dir / "processes.txt").write_text(
        "\n".join(process_lines) + ("\n" if process_lines else ""),
        encoding="utf-8",
    )
    note("processes", "captured processes.txt")

    repo_logs = {
        "Artifacts/DevRunner/clawbar-dev.log": ("clawbar-dev.tail.log", 200),
        "Artifacts/SmokeTests/clawbar-smoke.log": ("clawbar-smoke.tail.log", 200),
    }
    for relative, (dest_name, lines) in repo_logs.items():
        source = ROOT_DIR / relative
        if tail_to_file(source, run_dir / dest_name, lines):
            note("repo-artifacts", f"tailed {relative} -> {dest_name}")
        else:
            note("repo-artifacts", f"missing {relative}")

    harness_state = APP_STATE_PATH
    if copy_any(harness_state, run_dir / "app-state.json"):
        note("harness", "copied current app-state.json")
    else:
        note("harness", "no active app-state.json")

    latest_summaries = sorted(RUNS_ROOT.glob("*/summary.json"))[-5:]
    if latest_summaries:
        listing = "\n".join(str(path) for path in latest_summaries) + "\n"
        (run_dir / "recent-harness-summaries.txt").write_text(listing, encoding="utf-8")
        note("harness", "captured recent-harness-summaries.txt")

    user_log_files = {
        pathlib.Path.home() / "Library/Logs/Clawbar/openclaw-install.log": "openclaw-install.tail.log",
        pathlib.Path.home() / "Library/Logs/Clawbar/openclaw-uninstall.log": "openclaw-uninstall.tail.log",
    }
    for source, dest_name in user_log_files.items():
        if tail_to_file(source, run_dir / dest_name, 200):
            note("clawbar-user-logs", f"tailed {source}")
        else:
            note("clawbar-user-logs", f"missing {source}")

    tmp_openclaw = pathlib.Path("/tmp/openclaw")
    if tmp_openclaw.is_dir():
        files = sorted(path for path in tmp_openclaw.iterdir() if path.is_file())
        (run_dir / "tmp-openclaw-files.txt").write_text(
            "\n".join(str(path) for path in files) + ("\n" if files else ""),
            encoding="utf-8",
        )
        if files:
            tail_to_file(files[-1], run_dir / "openclaw-runtime.tail.log", 300)
            note("openclaw-runtime", f"tailed {files[-1]}")
        else:
            note("openclaw-runtime", "no files under /tmp/openclaw")
    else:
        note("openclaw-runtime", "missing /tmp/openclaw")

    openclaw_log_root = pathlib.Path.home() / ".openclaw/logs"
    if tail_to_file(openclaw_log_root / "config-audit.jsonl", run_dir / "config-audit.tail.jsonl", 200):
        note("openclaw-config", "tailed config-audit.jsonl")
    else:
        note("openclaw-config", "missing config-audit.jsonl")
    if copy_any(openclaw_log_root / "config-health.json", run_dir / "config-health.json"):
        note("openclaw-config", "copied config-health.json")
    else:
        note("openclaw-config", "missing config-health.json")

    unified_log = command_output(
        [
            "/usr/bin/log",
            "show",
            "--last",
            f"{args.last_minutes}m",
            "--style",
            "compact",
            "--predicate",
            'process == "Clawbar" OR eventMessage CONTAINS[c] "openclaw" OR processImagePath CONTAINS[c] "openclaw" OR senderImagePath CONTAINS[c] "openclaw"',
        ],
        check=False,
    )
    (run_dir / "unified-log.txt").write_text(unified_log.stdout, encoding="utf-8")
    (run_dir / "unified-log.stderr.txt").write_text(unified_log.stderr, encoding="utf-8")
    note("unified-log", f"captured last {args.last_minutes} minutes")

    qclaw_root = pathlib.Path.home() / "Library/Logs/QClaw/openclaw"
    if qclaw_root.is_dir():
        files = sorted(path for path in qclaw_root.iterdir() if path.is_file())
        (run_dir / "qclaw-log-files.txt").write_text(
            "\n".join(str(path) for path in files) + ("\n" if files else ""),
            encoding="utf-8",
        )
        if files:
            tail_to_file(files[-1], run_dir / "qclaw-openclaw.tail.log", 200)
            note("qclaw", f"tailed {files[-1]}")
    else:
        note("qclaw", f"missing {qclaw_root}")

    summary_txt = run_dir / "summary.txt"
    summary_txt.write_text("\n".join(summary_lines) + "\n", encoding="utf-8")

    summary = {
        "command": "logs collect",
        "status": "ok",
        "summary_path": str(summary_txt),
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result(
        "logs.collect",
        run_dir,
        summary_path,
        extra=[f"summary_path: {summary_txt}"],
    )
    return 0


def assert_logs_command(args: argparse.Namespace) -> int:
    file_path = pathlib.Path(args.file).resolve()
    assert_log_file(file_path, contains=args.contains or [], absent=args.absent or [])
    run_dir = create_run_directory("logs-assert")
    summary = {
        "command": "logs assert",
        "status": "ok",
        "file": str(file_path),
        "contains": args.contains or [],
        "absent": args.absent or [],
    }
    summary_path = write_summary(run_dir, summary)
    print_run_result("logs.assert", run_dir, summary_path, extra=[f"file: {file_path}"])
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Unified development and test harness for Clawbar."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    app_parser = subparsers.add_parser("app", help="Manage the local Clawbar app process.")
    app_subparsers = app_parser.add_subparsers(dest="app_command", required=True)

    def add_app_args(subparser: argparse.ArgumentParser, *, require_mode: bool) -> None:
        if require_mode:
            subparser.add_argument("--mode", choices=["menu-bar", "smoke", "ui"], default="menu-bar")
        else:
            subparser.add_argument("--mode", choices=["menu-bar", "smoke", "ui"])
        subparser.add_argument("--restart", action="store_true", help="Stop existing Clawbar instances first.")
        subparser.add_argument("--build", dest="build", action="store_true", default=True, help="Build before launch.")
        subparser.add_argument("--no-build", dest="build", action="store_false", help="Skip swift build.")
        subparser.add_argument("--wait-seconds", type=float, default=2.0, help="Seconds to wait after launch.")
        subparser.add_argument("--env", action="append", help="Additional KEY=VALUE environment overrides.")
        subparser.add_argument("--openclaw-state", choices=["missing", "installed"])
        subparser.add_argument("--openclaw-binary-path")
        subparser.add_argument("--openclaw-title")
        subparser.add_argument("--openclaw-detail")
        subparser.add_argument("--openclaw-excerpt")

    start_parser = app_subparsers.add_parser("start", help="Build and launch Clawbar in the background.")
    add_app_args(start_parser, require_mode=True)
    start_parser.set_defaults(handler=start_app_command)

    restart_parser = app_subparsers.add_parser("restart", help="Restart Clawbar using the last known or provided mode.")
    add_app_args(restart_parser, require_mode=False)
    restart_parser.set_defaults(handler=restart_app_command)

    stop_parser = app_subparsers.add_parser("stop", help="Stop the running Clawbar app.")
    stop_parser.add_argument("--binary-path", help="Override the binary path used for matching stale processes.")
    stop_parser.set_defaults(handler=stop_app_command)

    status_parser = app_subparsers.add_parser("status", help="Show the tracked app process state.")
    status_parser.set_defaults(handler=status_app_command)

    dev_loop_parser = app_subparsers.add_parser("dev-loop", help="Watch sources, rebuild, and relaunch on change.")
    dev_loop_parser.add_argument("--poll-interval", type=float, default=1.0)
    dev_loop_parser.set_defaults(handler=dev_loop_command)

    test_parser = subparsers.add_parser("test", help="Run Clawbar test flows.")
    test_subparsers = test_parser.add_subparsers(dest="test_command", required=True)

    unit_parser = test_subparsers.add_parser("unit", help="Run swift test, optionally with the coverage gate.")
    unit_parser.add_argument("--coverage-gate", action="store_true")
    unit_parser.add_argument("--filter")
    unit_parser.add_argument("--log-contains", action="append")
    unit_parser.add_argument("--log-absent", action="append")
    unit_parser.set_defaults(handler=unit_test_command)

    smoke_parser = test_subparsers.add_parser("smoke", help="Run the smoke window screenshot test.")
    smoke_parser.add_argument("--window-retries", type=int, default=40)
    smoke_parser.add_argument("--window-wait", type=float, default=0.5)
    smoke_parser.add_argument("--log-contains", action="append")
    smoke_parser.add_argument("--log-absent", action="append")
    smoke_parser.set_defaults(handler=smoke_test_command)

    integration_parser = test_subparsers.add_parser(
        "integration",
        help="Run grouped XCTest suites for channel/provider/gateway integration flows.",
    )
    integration_parser.add_argument("--suite", action="append", choices=["all", *sorted(INTEGRATION_SUITES.keys())])
    integration_parser.add_argument("--log-contains", action="append")
    integration_parser.add_argument("--log-absent", action="append")
    integration_parser.set_defaults(handler=integration_test_command)

    all_parser = test_subparsers.add_parser("all", help="Run unit + smoke + integration flows.")
    all_parser.set_defaults(handler=all_test_command)

    logs_parser = subparsers.add_parser("logs", help="Collect or assert Clawbar/OpenClaw logs.")
    logs_subparsers = logs_parser.add_subparsers(dest="logs_command", required=True)

    collect_parser = logs_subparsers.add_parser("collect", help="Collect the current diagnostics bundle.")
    collect_parser.add_argument("--last-minutes", type=int, default=15)
    collect_parser.set_defaults(handler=collect_logs_command)

    assert_parser = logs_subparsers.add_parser("assert", help="Assert required or forbidden patterns in a log file.")
    assert_parser.add_argument("--file", required=True)
    assert_parser.add_argument("--contains", action="append")
    assert_parser.add_argument("--absent", action="append")
    assert_parser.set_defaults(handler=assert_logs_command)

    return parser


def main() -> int:
    ensure_directory(ARTIFACTS_ROOT)
    ensure_directory(RUNS_ROOT)
    ensure_directory(STATE_ROOT)

    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.handler(args)
    except CommandFailure as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
