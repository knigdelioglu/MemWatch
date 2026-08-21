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

## Phase 3 - Menu Bar Experience

- [x] Minimal menu bar icon
- [x] Status colors
- [x] Detail popup
- [ ] Notification system

## Phase 4 - Storage Monitoring

- [ ] Detect internal storage devices
- [ ] Show disk capacity and free space
- [ ] Detect external drives
- [ ] Show external drive usage
- [ ] Add low storage warnings

## Phase 5 - Energy Monitoring

- [ ] Read battery and power information
- [ ] Calculate current watt consumption
- [ ] Detect adapter power input
- [ ] Detect battery charge/discharge flow
- [ ] Create animated power flow visualization
- [ ] Create live energy graph

## Phase 6 - Advanced Diagnostics

- [ ] Process memory snapshot
- [ ] Identify memory-heavy applications
- [ ] Timeline view
- [ ] Thermal monitoring
- [ ] CPU monitoring
- [ ] Fan status
- [ ] Launch-at-login option

## Phase 7 - Release Quality

- [ ] Performance tests
- [ ] Battery impact tests
- [ ] macOS packaging
- [ ] Release build
