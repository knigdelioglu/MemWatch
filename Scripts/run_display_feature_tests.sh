#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}/.."
OUTPUT_DIR="$(mktemp -d /private/tmp/memwatch-display-tests.XXXXXX)"
trap 'rm -rf "$OUTPUT_DIR"' EXIT

swiftc \
    -parse-as-library \
    -module-name MemWatchDisplaySmoke \
    -module-cache-path "$OUTPUT_DIR/ModuleCache" \
    -o "$OUTPUT_DIR/display-feature-smoke" \
    "$ROOT_DIR/Display/Preferences/AmbientSyncModels.swift" \
    "$ROOT_DIR/Display/App/DisplayPreferencesMigration.swift" \
    "$ROOT_DIR/Display/BrightnessEngine/BrightnessCurve.swift" \
    "$ROOT_DIR/Display/DisplayControl/Brightness/BrightnessAutoController.swift" \
    "$ROOT_DIR/Display/DisplayControl/Brightness/M1DDCBrightnessWriteStatus.swift" \
    "$ROOT_DIR/Display/DisplayControl/Brightness/BrightnessState.swift" \
    "$ROOT_DIR/Display/DisplayControl/Brightness/BrightnessAutoLoopPlanner.swift" \
    "$ROOT_DIR/Display/DisplayControl/Brightness/DDCBrightnessParsing.swift" \
    "$ROOT_DIR/Display/BrightnessEngine/LuxFilter.swift" \
    "$ROOT_DIR/Display/DisplayControl/Brightness/DDCBrightnessScale.swift" \
    "$ROOT_DIR/Display/DisplayControl/DisplayConnectionState.swift" \
    "$ROOT_DIR/Display/DisplayFeature.swift" \
    "$ROOT_DIR/Display/System/KeepAwakeController.swift" \
    "$ROOT_DIR/Display/System/KeepAwakeFeatureController.swift" \
    "$ROOT_DIR/Core/Polling/PollingScheduler.swift" \
    "$ROOT_DIR/Tests/DisplayFeatureSmoke.swift" \
    -framework AppKit \
    -framework IOKit

"$OUTPUT_DIR/display-feature-smoke"
