# MemWatch Validation

## Sprint 1 automated checks

The macOS CI workflow validates the first monitoring slice on a real macOS GitHub runner.

### Build gate

```bash
xcodebuild \
  -project MemWatch.xcodeproj \
  -scheme MemWatch \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

This gate verifies that the native SwiftUI menu bar application and its Mach/Darwin memory collector compile together as a macOS application.

## Merged Display feature smoke gate

Run the deterministic display-feature checks from the repository root:

```bash
Scripts/run_display_feature_tests.sh
```

This covers the brightness curve, lux filtering, DDC percentage scaling, capability degradation, automatic-brightness preflight, display-connection safety policy, keep-awake preference persistence, scheduler ownership, and AmbientSync preference migration. The CI workflow also runs the source-level merge architecture contract checks for the single status item, shared service container, bundled HiDPI reference, and removal of the unused duplicate recovery controller.

The Xcode project is the only runtime build system for MemWatch. The standalone smoke scripts intentionally compile only deterministic feature seams; they do not claim physical ALS, DDC, HiDPI, or display-disconnect validation.

### Collector smoke gate

The CI workflow also compiles and runs `Tests/MemoryCollectorSmoke.swift` directly against `MemorySnapshot` and `MemoryCollector`.

The smoke gate requires:

- physical RAM > 0
- used RAM <= physical RAM
- available RAM <= physical RAM
- used RAM + available headroom == physical RAM
- App Memory, Wired, Compressed, Cached Files, and True Free are bounded by physical RAM
- swap used <= swap total when swap is configured

For diagnostics, CI prints the collector snapshot together with `vm_stat` and `sysctl vm.swapusage` output from the same macOS runner.

## Local Activity Monitor comparison

Activity Monitor uses Apple-internal presentation logic, so MemWatch does not claim bit-for-bit equivalence for the aggregate `Memory Used` number or Apple's private memory-pressure graph.

When validating on a development Mac, compare the following at approximately the same moment:

| MemWatch | Activity Monitor / macOS reference |
| --- | --- |
| Physical RAM | Physical Memory |
| Memory Used | Memory Used |
| App Memory | Memory Used > App Memory |
| Compressed | Memory Used > Compressed |
| Wired | Memory Used > Wired Memory |
| Cached Files | Cached Files |
| Available headroom | Free/reclaimable headroom; do not treat it as Apple's private pressure score |
| Swap Used | Swap Used |
| Swap-in / Swap-out movement | `vm_stat` / Mach `swapins`, `swapouts` deltas |

Small differences are expected because values change continuously and the tools may sample at different instants.

For a single point-in-time diagnostic dump from the built app, run:

```bash
/path/to/MemWatch.app/Contents/MacOS/MemWatch --memory-diagnostics
```

The dump includes the system accounting buckets and each returned process row's
PID, group, process count, memory metric, and physical-footprint/RSS-fallback
source. In separate terminals, compare it with `vm_stat`, `sysctl vm.swapusage`,
and `top -o mem` taken at roughly the same moment.

## Product rule

MemWatch's `Normal / Warning / Critical` state is a documented MemWatch health classification. It must not be presented as Apple's private Activity Monitor Memory Pressure algorithm unless a public Apple API provides that exact state.
