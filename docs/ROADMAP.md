# MemWatch Roadmap

## Phase 0 - Project Foundation

- [x] Repository created
- [x] Documentation structure created
- [x] Native Xcode project initialization
- [x] macOS menu bar skeleton
- [x] Shared Xcode scheme
- [x] macOS CI build gate

## Phase 1 - Core Memory Monitoring — Sprint 1 Complete

- [x] Read physical RAM information
- [x] Read used/free memory
- [x] Read compressed memory
- [x] Read wired memory
- [x] Read cached memory
- [x] Read swap total/used/free
- [x] Read Mach swap-in / swap-out counters
- [x] Add MemWatch memory pressure fallback classification
- [x] Observe native macOS memory-pressure events through public DispatchSource API
- [x] Add collector smoke validation on a macOS runner
- [x] Print `vm_stat` and `sysctl vm.swapusage` reference data in CI
- [x] Document Activity Monitor comparison protocol

## Phase 2 - Swap Intelligence — Sprint 2 Complete

- [x] Detect active swap usage
- [x] Track swap-in / swap-out changes
- [x] Separate idle swap from active memory pressure with sustained sampling
- [x] Create smart warning algorithm
- [x] Add hysteresis so transient spikes do not cause warning flicker
- [x] Store a 60-second in-memory history window
- [x] Distinguish idle swap, readback, active swap, pressure, and critical states
- [x] Add deterministic swap-intelligence scenario tests to macOS CI

## Phase 3 - Menu Bar Experience — Sprint 3 Complete

- [x] Minimal menu bar icon
- [x] Status colors
- [x] Detail popup
- [x] Smart macOS notification system
- [x] Alert only for sustained active swap, memory pressure, and critical states
- [x] Notify immediately when severity escalates
- [x] Add 15-minute repeat cooldown for persistent states
- [x] Send one recovery notification after sustained pressure clears
- [x] Persist notification enable/disable preference
- [x] Show macOS notification authorization state in the menu bar
- [x] Add deterministic notification-policy tests to macOS CI
- [x] Run as a menu-bar-only accessory app without a Dock icon

## Phase 4 - Storage Monitoring — Sprint 4 Complete

- [x] Detect internal storage devices
- [x] Show disk capacity, used space, free space, and usage percentage
- [x] Detect external local drives automatically
- [x] Show external drive usage alongside internal storage
- [x] Refresh mounted storage every 30 seconds
- [x] Classify normal, low-space, and critical-space states
- [x] Add low storage warnings with severity escalation
- [x] Add 6-hour cooldown for persistent storage warnings
- [x] Add storage collector smoke validation on a macOS runner
- [x] Add deterministic storage notification-policy tests to macOS CI

## Phase 5 - Energy Monitoring — Sprint 5 Complete

- [x] Read battery and power-source information through IOKit
- [x] Calculate live battery-side watts from electrical current × voltage
- [x] Show live Mac draw while running on battery
- [x] Detect AC adapter presence and show adapter rated wattage
- [x] Detect battery charging, discharging, and idle flow states
- [x] Avoid treating adapter rated wattage as instantaneous wall draw
- [x] Keep a 10-minute in-memory power history
- [x] Create animated Adapter → Mac / Adapter → Battery / Battery → Mac flow visualization
- [x] Create live power graph with average wattage
- [x] Add deterministic watt/flow tests to macOS CI
- [x] Add power collector smoke validation on a macOS runner

## Phase 6 - Advanced Diagnostics — Sprint 6 Complete

- [x] Capture process resident-memory snapshots
- [x] Identify and rank memory-heavy running applications
- [x] Refresh expensive process snapshots every 30 seconds
- [x] Add 10-minute CPU + RAM timeline
- [x] Monitor system thermal state through public ProcessInfo API
- [x] Monitor live system CPU usage from Mach host CPU counters
- [x] Show Low Power Mode state
- [x] Treat fan RPM as unavailable rather than fabricating telemetry when no stable public macOS API exists
- [x] Add launch-at-login control with SMAppService
- [x] Show login-item approval state
- [x] Add system diagnostics collector smoke validation to macOS CI

## Phase 7 - Release Quality

- [ ] Performance tests
- [ ] Battery impact tests
- [ ] macOS packaging
- [ ] Release build
