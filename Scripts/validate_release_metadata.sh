#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="${VERSION_FILE:-$ROOT_DIR/version.env}"

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "version.env not found at $VERSION_FILE" >&2
  exit 1
fi

source "$VERSION_FILE"

if [[ -z "${MARKETING_VERSION:-}" ]]; then
  echo "MARKETING_VERSION is missing from $VERSION_FILE" >&2
  exit 1
fi

if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "MARKETING_VERSION must be semantic version x.y.z, got: $MARKETING_VERSION" >&2
  exit 1
fi

if [[ -z "${BUILD_NUMBER:-}" ]]; then
  echo "BUILD_NUMBER is missing from $VERSION_FILE" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "BUILD_NUMBER must be numeric, got: $BUILD_NUMBER" >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  TAG="$1"
  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Release tag must be in the form v<version>, got: $TAG" >&2
    exit 1
  fi

  TAG_VERSION="${TAG#v}"
  if [[ "$TAG_VERSION" != "$MARKETING_VERSION" ]]; then
    echo "Tag/version mismatch: tag=$TAG version.env=$MARKETING_VERSION" >&2
    exit 1
  fi
fi

echo "Release metadata OK: version=$MARKETING_VERSION build=$BUILD_NUMBER"
