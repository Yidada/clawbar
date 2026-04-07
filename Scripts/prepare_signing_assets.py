#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import os
import re
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Prepare ignored local signing files inside the repository from an export "
            "bundle that contains either KEY=value files or raw .p12/.p8 assets."
        )
    )
    parser.add_argument("--source-dir", required=True, help="Directory containing the signing export bundle.")
    parser.add_argument(
        "--output-dir",
        default=".local/signing",
        help="Ignored output directory to create inside the repository. Defaults to .local/signing.",
    )
    parser.add_argument("--team-id", required=True, help="Apple Developer Team ID.")
    parser.add_argument("--signing-identity", required=True, help="Developer ID Application identity to use locally.")
    parser.add_argument("--notary-key-id", required=True, help="App Store Connect API key ID.")
    parser.add_argument("--notary-issuer-id", required=True, help="App Store Connect API issuer ID.")
    return parser.parse_args()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    os.chmod(path, 0o700)


def write_secret_file(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)
    os.chmod(path, 0o600)


def write_secret_text(path: Path, content: str) -> None:
    write_secret_file(path, content.encode("utf-8"))


def unwrap_assignment(raw_text: str, expected_name: str | None = None) -> str:
    text = raw_text.strip()
    if "=" not in text:
        return text

    match = re.match(r"^([A-Z0-9_]+)=(.*)$", text, re.DOTALL)
    if not match:
        return text

    name, value = match.groups()
    if expected_name and name != expected_name:
        raise ValueError(f"Expected {expected_name} assignment but found {name}.")
    return value.strip()


def read_wrapped_value(path: Path, expected_name: str) -> str:
    return unwrap_assignment(path.read_text(encoding="utf-8"), expected_name=expected_name)


def resolve_cert_base64(source_dir: Path) -> str:
    wrapped = source_dir / "gitlab-variable-apple-developer-id-cert-base64.txt"
    if wrapped.exists():
        return read_wrapped_value(wrapped, "APPLE_DEVELOPER_ID_CERT_BASE64")

    p12_files = sorted(source_dir.glob("*.p12"))
    if not p12_files:
        raise FileNotFoundError("Could not find a Developer ID certificate bundle (.p12).")
    return base64.b64encode(p12_files[0].read_bytes()).decode("ascii")


def resolve_cert_password(source_dir: Path) -> str:
    wrapped = source_dir / "gitlab-variable-apple-developer-id-cert-password.txt"
    if not wrapped.exists():
        raise FileNotFoundError("Could not find gitlab-variable-apple-developer-id-cert-password.txt.")
    return read_wrapped_value(wrapped, "APPLE_DEVELOPER_ID_CERT_PASSWORD")


def resolve_notary_key_bytes(source_dir: Path) -> bytes:
    wrapped = source_dir / "gitlab-variable-apple-notary-api-key-base64.txt"
    if wrapped.exists():
        value = read_wrapped_value(wrapped, "APPLE_NOTARY_API_KEY_BASE64")
        return base64.b64decode(value)

    p8_files = sorted(source_dir.glob("AuthKey_*.p8"))
    if not p8_files:
        raise FileNotFoundError("Could not find the App Store Connect API private key (.p8).")
    return p8_files[0].read_bytes()


def main() -> None:
    args = parse_args()

    source_dir = Path(args.source_dir).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    github_env_dir = output_dir / "github-environment" / "release-signing"
    notary_dir = output_dir / "notary"

    ensure_dir(output_dir)
    ensure_dir(github_env_dir)
    ensure_dir(notary_dir)

    cert_base64 = resolve_cert_base64(source_dir)
    cert_password = resolve_cert_password(source_dir)
    notary_key_bytes = resolve_notary_key_bytes(source_dir)
    notary_key_base64 = base64.b64encode(notary_key_bytes).decode("ascii")

    if not notary_key_bytes.startswith(b"-----BEGIN PRIVATE KEY-----"):
        raise ValueError("Resolved notary API key is not a PEM private key.")

    notary_key_path = notary_dir / f"AuthKey_{args.notary_key_id}.p8"
    write_secret_file(notary_key_path, notary_key_bytes)

    secret_values = {
        "APPLE_DEVELOPER_ID_CERT_BASE64": cert_base64,
        "APPLE_DEVELOPER_ID_CERT_PASSWORD": cert_password,
        "APPLE_TEAM_ID": args.team_id,
        "APPLE_NOTARY_KEY_ID": args.notary_key_id,
        "APPLE_NOTARY_ISSUER_ID": args.notary_issuer_id,
        "APPLE_NOTARY_API_KEY_BASE64": notary_key_base64,
    }

    for name, value in secret_values.items():
        write_secret_text(github_env_dir / name, value)

    env_lines = [f"{name}={value}" for name, value in secret_values.items()]
    write_secret_text(output_dir / "github-environment" / "release-signing.env", "\n".join(env_lines) + "\n")

    local_env = "\n".join(
        [
            f'export SIGNING_IDENTITY="{args.signing_identity}"',
            'export SIGNING_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"',
            f'export APPLE_TEAM_ID="{args.team_id}"',
            f'export APPLE_NOTARY_KEY_ID="{args.notary_key_id}"',
            f'export APPLE_NOTARY_ISSUER_ID="{args.notary_issuer_id}"',
            f'export APPLE_NOTARY_API_KEY_PATH="{notary_key_path}"',
            "",
        ]
    )
    write_secret_text(output_dir / "local-notary.env", local_env)

    summary = "\n".join(
        [
            "Prepared local signing assets:",
            f"  Source bundle: {source_dir}",
            f"  Local env: {output_dir / 'local-notary.env'}",
            f"  Notary key: {notary_key_path}",
            f"  GitHub environment secret files: {github_env_dir}",
            "",
            "Next steps:",
            f"  1. source {output_dir / 'local-notary.env'}",
            "  2. ./Scripts/sign_and_notarize.sh",
            "  3. In GitHub, create environment release-signing and copy the six files from github-environment/release-signing/ into matching environment secrets.",
        ]
    )
    print(summary)


if __name__ == "__main__":
    main()
