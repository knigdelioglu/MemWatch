# MemWatch + AmbientSync Merge Architecture

## Scope

MemWatch remains the product, bundle, Xcode project, menu-bar shell, cleanup
owner, and privileged-helper owner. AmbientSync is migrated as the Display
feature without retaining its executable entry point, status item, launch
agent, or preferences window.

Audit baseline: MemWatch is an Xcode macOS application with one app target and
one `MemWatchPrivilegedHelper` target. AmbientSync is a Swift 6 macOS 13
executable package with one executable target, one test target, one status-bar
application delegate, and 16,038 lines across its Swift source tree. The
AmbientSync display implementation is retained as the low-level source of
truth where practical; application orchestration is moved to the unified app.

## Migration map

| Existing responsibility | Unified owner | Boundary and proof |
| --- | --- | --- |
| MemWatch app startup and accessory policy | `AppDelegate` in `MemWatchApp.swift` | The only `NSApplicationDelegate`; sets `.accessory`, creates `AppServices`, and owns shutdown. Xcode app target is the runtime boundary. |
| MemWatch monitoring polling | `PollingScheduler` + `MonitoringService` | One shared main-run-loop scheduler; system health registers one 5-second job. `MonitoringService.stop()` unregisters it. |
| AmbientSync polling and display wake events | `DisplayCoordinator` | One idempotent Display job and centralized workspace observers. `start()`/`stop()` are the feature lifecycle. |
| AmbientSync brightness, ALS, DDC, EDID, HiDPI, connection, volume, and keep-awake engines | `Display/` sources | Low-level controllers remain separate and are not called from SwiftUI. Display failures update capability/state and do not escape into app startup. |
| AmbientSync `AppState` | `DisplayCoordinator` | The old app delegate is not compiled. Display state and orchestration live behind `DisplayFeatureControlling`; it does not create an app, window, or status item. |
| AmbientSync status item/popover | MemWatch `StatusBarController` | Exactly one `NSStatusItem`; Display is a dashboard module/detail route in the existing popover. |
| AmbientSync launch agent | MemWatch `LaunchAtLoginService` | The app uses one `SMAppService.mainApp` setting. A versioned migration removes the known legacy AmbientSync launch-agent file and attempts a one-time unload. |
| AmbientSync JSON/preferences | `AmbientSyncStore` + `DisplayPreferencesMigration` | The existing `AmbientSync.AppPreferences` payload and legacy scalar keys are read before defaults. Migration is versioned and idempotent. |
| MemWatch and AmbientSync power-source reads | `Core/Power/PowerSourceReader` | One IOKit power-source snapshot adapter is shared by system energy telemetry and Display keep-awake policy; each caller retains its own domain interpretation. |
| Privileged cleanup | Existing MemWatch helper target | Display operations remain unprivileged. No second helper or daemon is introduced. |
| AmbientSync diagnostic CLI | Unified app early launch router | Existing flags are routed before normal feature startup. Reports use Application Support or the app bundle rather than source-relative paths. |

## Runtime capability model

`DisplayCapabilities` is the display feature's authoritative availability
snapshot. It distinguishes ambient light, internal brightness, external
display, DDC/`m1ddc`, HiDPI/private APIs, software connection, volume, and
keep-awake. The Display UI derives enabled/disabled state from this snapshot.

The following failure policy is intentional:

```text
private API / m1ddc / ALS unavailable
    -> Display capability becomes unavailable or degraded
    -> the relevant control explains the next action
    -> MemWatch monitoring, cleanup, notifications, and tray operation continue
```

Display connection operations retain the existing fail-closed guards: the
last active display cannot be disconnected, IDs are re-enumerated, target
identity is fingerprinted, mirror/topology changes are reconciled, and retry
counts remain bounded.

## Unified lifecycle

```text
MemWatchApp
  -> async diagnostic preflight (when a CLI flag is present)
  -> AppDelegate
       -> AppServices
            -> PollingScheduler
            -> MonitoringService
            -> DisplayCoordinator
            -> CleanupCoordinator
            -> CapabilityRegistry
       -> StatusBarController (the only NSStatusItem)
```

The diagnostic preflight runs before `NSApplication.shared` is initialized, so
headless diagnostic invocations do not accidentally bootstrap the GUI shell.
The app delegate only coordinates lifecycle and shell wiring. Feature policy
stays in the owning service/coordinator. `AppServices.stop()` releases display
observers, timers, keep-awake assertions, and monitoring work on termination.

## UX contract

### User goal

From one menu-bar popover, a Mac user can understand system health quickly,
change common display/keep-awake controls safely, and open advanced display or
cleanup workflows without hunting across two applications.

### Primary flow

1. Click the single MemWatch status item and see Mac health first.
2. Use the compact Display summary for common brightness/auto-brightness and
   keep-awake actions, or open Display details for advanced controls.
3. Read capability explanations when hardware/private APIs are unavailable;
   retry or open diagnostics from the same Display surface.

### Screen structure and states

- Overview: critical health, memory/swap, storage/energy/system summaries,
  Display summary, Cleanup entry, and a refresh action.
- Display detail: display identity/lux, internal or external brightness,
  auto-brightness, volume/mute, HiDPI, connection, keep-awake, and diagnostics.
- Settings: one window with General, System, Display, and Diagnostics sections.
- Loading/partial: show `Checking…` or unavailable values rather than fake
  percentages.
- Disabled/degraded: controls are visibly disabled and include the capability
  reason (for example, install `m1ddc` for DDC controls).
- Error: preserve the current state, show an actionable status, and avoid
  notification loops for repeated display failures.

### Interaction and accessibility rules

- Critical system state always outranks Display state in the tray.
- Common controls have text labels and accessible names; important actions are
  not icon-only.
- Disconnect/reconnect is disabled when safety validation rejects the target.
- Existing reduced-motion behavior is retained for tray transitions.
- The popover keeps a fixed laptop-friendly size, uses progressive disclosure
  for diagnostics, and preserves the established SwiftUI/AppKit control style.

## Validation map

| Requirement | Verification |
| --- | --- |
| One app/status item/lifecycle | `xcodebuild -list`, app build, static search for `NSStatusBar.system.statusItem` and `NSApplicationDelegate` in the Display tree, and code review of `AppDelegate`. |
| Display capability isolation | Display capability unit/smoke tests plus app build; physical private API and monitor checks remain explicitly hardware-dependent. |
| Preferences preservation | `DisplayPreferencesMigration` tests for old-key-to-new-key behavior and idempotence; existing `AmbientSync.AppPreferences` is retained. |
| Scheduler/lifecycle idempotence | `PollingScheduler` tests/smoke assertions and coordinator `start()`/`stop()` ownership review. |
| Existing MemWatch health/cleanup | Existing smoke tests and canonical app/helper build. |
| Resources and diagnostics | Bundle resource smoke check and diagnostic-router invocation/static verification. |

## Physical validation boundary

The repository can verify compilation and policy logic, but ALS readings,
external DDC/CI writes, monitor volume, real HiDPI mode changes, software
disconnect/reconnect, and sleep/wake behavior require a physical supported Mac
and display. These paths must never be represented as passing hardware tests
based only on mocks or a successful build.
