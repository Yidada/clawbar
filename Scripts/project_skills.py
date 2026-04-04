#!/usr/bin/env python3
from __future__ import annotations
import argparse
import glob
import json
import os
import shutil
import sys
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve()
PROJECT_ROOT = SCRIPT_PATH.parent.parent
MANIFEST_PATH = PROJECT_ROOT / ".agents" / "skills" / "registry.json"
SKILL_ROOT = PROJECT_ROOT / ".agents" / "skills"
DEFAULT_SEARCH_ROOTS = [
    "$CODEX_HOME/skills",
    "~/.agents/skills",
    "~/.codex/plugins/cache/openai-curated/*/*/skills",
]


def load_manifest() -> dict:
    if not MANIFEST_PATH.is_file():
        raise SystemExit(f"Missing manifest: {MANIFEST_PATH}")

    with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def expand_pattern(value: str) -> str:
    codex_home = os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))
    return os.path.expanduser(os.path.expandvars(value.replace("$CODEX_HOME", codex_home)))


def tracked_skills(manifest: dict) -> list[dict]:
    skills = manifest.get("skills")
    if not isinstance(skills, list):
        raise SystemExit(f"Invalid manifest: {MANIFEST_PATH}")
    return skills


def skill_dir(entry: dict) -> Path:
    return SKILL_ROOT / entry["name"]


def resolve_source(entry: dict) -> Path | None:
    if entry.get("mode") != "vendored":
        return None

    explicit_source = entry.get("source")
    if explicit_source:
        source_dir = Path(expand_pattern(explicit_source))
        if (source_dir / "SKILL.md").is_file():
            return source_dir.resolve()
        return None

    upstream_name = entry.get("upstreamName", entry["name"])
    search_roots = entry.get("searchRoots", DEFAULT_SEARCH_ROOTS)

    for pattern in search_roots:
        for root in sorted(glob.glob(expand_pattern(pattern))):
            candidate = Path(root) / upstream_name
            if (candidate / "SKILL.md").is_file():
                return candidate.resolve()

    return None


def find_entries(manifest: dict, names: list[str]) -> list[dict]:
    entries = tracked_skills(manifest)
    if not names:
        return entries

    by_name = {entry["name"]: entry for entry in entries}
    missing = [name for name in names if name not in by_name]
    if missing:
        raise SystemExit(f"Unknown skills in manifest: {', '.join(missing)}")
    return [by_name[name] for name in names]


def list_command(manifest: dict) -> int:
    entries = tracked_skills(manifest)
    print("name\tmode\tcategory\tlocal\tsource")
    for entry in entries:
        local_dir = skill_dir(entry)
        local_state = "present" if (local_dir / "SKILL.md").is_file() else "missing"
        source = "-"
        resolved = resolve_source(entry)
        if resolved is not None:
            source = str(resolved)
        elif entry.get("mode") == "vendored":
            source = "unresolved"
        print(
            "\t".join(
                [
                    entry["name"],
                    entry.get("mode", "owned"),
                    entry.get("category", "-"),
                    local_state,
                    source,
                ]
            )
        )
    return 0


def check_command(manifest: dict) -> int:
    errors: list[str] = []
    tracked_names: set[str] = set()

    for entry in tracked_skills(manifest):
        name = entry["name"]
        tracked_names.add(name)
        local_dir = skill_dir(entry)
        local_skill = local_dir / "SKILL.md"

        if entry.get("mode") == "owned":
            if not local_skill.is_file():
                errors.append(f"Owned skill missing locally: {local_dir}")
            continue

        resolved = resolve_source(entry)
        if resolved is None:
            errors.append(f"Vendored skill source unresolved: {name}")
        if not local_skill.is_file():
            errors.append(f"Vendored skill not synced locally: {local_dir}")

    for child in sorted(SKILL_ROOT.iterdir()):
        if not child.is_dir():
            continue
        if child.name.startswith("."):
            continue
        if child.name not in tracked_names:
            errors.append(f"Local skill directory is unmanaged: {child}")

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1

    print("Project skills manifest is consistent.")
    return 0


def sync_entry(entry: dict) -> None:
    resolved = resolve_source(entry)
    if resolved is None:
        raise SystemExit(f"Could not resolve source for vendored skill: {entry['name']}")

    target = skill_dir(entry)
    temp_target = target.parent / f".{target.name}.tmp"

    if temp_target.exists():
        shutil.rmtree(temp_target)

    shutil.copytree(resolved, temp_target, symlinks=False, copy_function=shutil.copy2)

    if target.exists():
        shutil.rmtree(target)

    temp_target.rename(target)
    print(f"Synced {entry['name']} <- {resolved}")


def sync_command(manifest: dict, names: list[str]) -> int:
    entries = [entry for entry in find_entries(manifest, names) if entry.get("mode") == "vendored"]

    if not entries:
        print("No vendored skills selected for sync.")
        return 0

    for entry in entries:
        sync_entry(entry)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Manage project-local skills tracked in .agents/skills/registry.json."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list", help="List tracked project skills.")
    subparsers.add_parser("check", help="Validate the project skills manifest against the local tree.")

    sync_parser = subparsers.add_parser("sync", help="Copy vendored skills into .agents/skills.")
    sync_parser.add_argument("names", nargs="*", help="Optional subset of vendored skill names.")

    args = parser.parse_args()
    manifest = load_manifest()

    if args.command == "list":
        return list_command(manifest)
    if args.command == "check":
        return check_command(manifest)
    if args.command == "sync":
        return sync_command(manifest, args.names)

    parser.error(f"Unsupported command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
