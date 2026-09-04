#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}/../.."
TMP_DIR="$(mktemp -d /private/tmp/memwatch-thermal-probe.XXXXXX)"
trap 'rm -f "$TMP_DIR/thermal-hardware-probe"; rmdir "$TMP_DIR" 2>/dev/null || true' EXIT

cd "$ROOT_DIR"

xcrun swiftc \
    -Onone \
    -g \
    -module-name ThermalHardwareProbe \
    -module-cache-path "$TMP_DIR/ModuleCache" \
    Scripts/ThermalHardwareProbe/main.swift \
    -framework IOKit \
    -o "$TMP_DIR/thermal-hardware-probe"

exec "$TMP_DIR/thermal-hardware-probe" "$@"
