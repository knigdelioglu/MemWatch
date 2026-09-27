#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/memwatch-mole-cleanup-tests.XXXXXX")"
TEST_BINARY="$TEST_DIR/MoleCleanupServiceTests"
trap 'rm -rf "$TEST_DIR"' EXIT

xcrun swiftc \
  -module-cache-path "$TEST_DIR/ModuleCache" \
  -framework Combine \
  "$ROOT_DIR/Services/MoleCleanupService.swift" \
  "$ROOT_DIR/Tests/MoleCleanupServiceTests.swift" \
  -o "$TEST_BINARY"

"$TEST_BINARY"
