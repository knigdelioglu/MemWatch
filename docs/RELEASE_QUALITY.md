# MemWatch Release Quality

## Automated release-quality gates

Every pull request to `main` runs on a real GitHub macOS runner and must pass:

- Debug Xcode build
- Menu-bar-only / no-Dock configuration check
- Memory collector smoke test
- Storage collector smoke test
- Power model + power collector tests
- System diagnostics collector smoke test
- Swap Intelligence tests
- Memory and storage notification-policy tests
- Collector performance budgets
- Background polling cadence / battery-impact regression guard
- Universal Release build (`arm64` + `x86_64`)
- Ad-hoc code-sign verification
- DMG creation, verification, mount and app-presence check
- SHA-256 generation for the DMG

## Performance budget

The CI performance gate intentionally uses broad ceilings so normal GitHub-runner variability does not create flaky builds while still catching pathological regressions.

Current limits:

- 200 memory polls: < 5 seconds total
- 100 power polls: < 5 seconds total
- 100 lightweight CPU/thermal polls: < 5 seconds total
- One running-app memory snapshot: < 3 seconds
- 50 combined normal monitoring cycles: < 5 seconds total

These are regression ceilings, not claims about typical runtime latency.

## Battery-impact safeguards

MemWatch is a monitoring utility, so monitoring must not become the workload.

Current background cadence:

- Core memory, power and lightweight CPU/thermal sample: every 5 seconds
- Storage scan: no more frequently than every 30 seconds
- Running-application memory scan: no more frequently than every 30 seconds
- Power and system histories: bounded to 120 samples (approximately 10 minutes at the normal cadence)

CI fails if these intervals are accidentally made more aggressive or if the history buffers become unbounded.

### Physical MacBook validation protocol

A real battery-drain comparison cannot be made reliably on a GitHub-hosted macOS runner because the runner is not a controlled battery-powered MacBook. Before a public release, use the following A/B protocol on a physical MacBook:

1. Charge to the same starting battery level and disconnect AC power.
2. Keep display brightness, Low Power Mode, network state and foreground workload unchanged.
3. Run a 30-minute baseline with MemWatch not running.
4. Repeat for 30 minutes with MemWatch running and its menu closed.
5. Compare battery percentage change and macOS Energy Impact / CPU observations.
6. Repeat at least three times and compare medians rather than a single run.
7. Repeat once with the MemWatch popover open because animated UI graphs intentionally do more rendering work while visible.

The background/menu-closed case is the primary release criterion.

## Packaging

`Scripts/package_release.sh` builds a universal Release app and creates:

- `dist/MemWatch.dmg`
- `dist/MemWatch.dmg.sha256`

The script verifies both architectures, applies an ad-hoc signature for package consistency, verifies the signature, verifies the DMG, mounts the DMG and confirms that `MemWatch.app` is present.

## Distribution signing and notarization

The CI-generated DMG is **not** a Developer ID signed and Apple-notarized public distribution package.

For a public release without Gatekeeper warnings, the final distribution step still requires:

- Apple Developer Program membership
- Developer ID Application certificate
- Code signing with that Developer ID identity
- Apple notarization (`notarytool`)
- Stapling the notarization ticket

MemWatch deliberately does not label an ad-hoc signed artifact as notarized or production-signed.
