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
- swap used <= swap total when swap is configured

For diagnostics, CI prints the collector snapshot together with `vm_stat` and `sysctl vm.swapusage` output from the same macOS runner.

## Local Activity Monitor comparison

Activity Monitor uses Apple-internal presentation logic, so MemWatch does not claim bit-for-bit equivalence for the aggregate `Memory Used` number or Apple's private memory-pressure graph.

When validating on a development Mac, compare the following at approximately the same moment:

| MemWatch | Activity Monitor / macOS reference |
| --- | --- |
| Physical RAM | Physical Memory |
| Compressed | Memory Used > Compressed |
| Wired | Memory Used > Wired Memory |
| Swap Used | Swap Used |
| Swap-in / Swap-out movement | `vm_stat` / Mach `swapins`, `swapouts` deltas |

Small differences are expected because values change continuously and the tools may sample at different instants.

## Product rule

MemWatch's `Normal / Warning / Critical` state is a documented MemWatch health classification. It must not be presented as Apple's private Activity Monitor Memory Pressure algorithm unless a public Apple API provides that exact state.
