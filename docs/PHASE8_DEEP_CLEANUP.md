# Phase 8 — Deep Storage & Cleanup

Phase 8 is one complete private-use delivery. The implementation is split into internal development phases only; Phase 8 is not considered complete or releasable until every acceptance gate in this document is satisfied.

## Product posture

MemWatch is a private macOS utility for the owner's machines. Phase 8 may therefore use Full Disk Access, a privileged helper, system command backends, and carefully isolated undocumented/private backends when they provide a concrete technical advantage. Private access does not relax deletion safety.

Hard boundaries remain:

- Never bypass SIP or the sealed system volume.
- Never expose a generic root `delete(path:)` primitive over XPC.
- Never classify unknown data as safe merely because it is large or old.
- Never treat AI model weights, personal documents, Photos-library internals, mail databases, source code, or unknown application databases as automatic junk.
- Never run recursive cleanup scans from the normal 5-second/30-second monitoring cadence.

## Internal implementation phases

### 8A — Cleanup foundation

- Typed cleanup domain model.
- Scanner protocol and scan context.
- Central rule catalog.
- Canonical-path and symlink validation.
- File identity capture for later TOCTOU protection.
- Safety engine that can only make scanner output more restrictive.
- Allocated/logical size accounting.
- Cancellable scan engine.

### 8B — User-space and developer scanners

- User caches and logs, including sandbox/container caches.
- Xcode: DerivedData, module/documentation caches, Device Support, simulator-related candidates, SwiftPM and preview/test artifacts.
- Homebrew, npm, Yarn, pnpm, pip, Poetry, uv, Cargo, Go, CocoaPods, Docker, VS Code, JetBrains, Maven, Gradle, Bun, Deno and mise.
- Project artifact discovery for node_modules, build outputs, target, .build, virtual environments, Pods, vendor, CMake/Gradle/Flutter artifacts and related regenerable directories.
- Trash and download/installer intelligence.
- iOS/iPadOS device backups.
- AI cache/temp/model classification for local-model tools.

### 8C — Deep attribution scanners

- Installed-application inventory.
- User and system application-leftover attribution with confidence scoring.
- Orphan LaunchAgent/LaunchDaemon detection.
- Mail attachment-cache classification where access permits.
- Diagnostic/crash-report cleanup rules.
- Large/old-file analysis.
- Exact duplicate detection with size grouping, partial hash and full SHA-256 confirmation.
- Hardlink/APFS-aware reclaim accounting.
- Similar-image clustering using on-device Vision APIs; never auto-selected.

### 8D — Privileged helper and deep system operations

- Dedicated privileged helper target installed/managed with ServiceManagement on supported macOS versions.
- Narrow typed XPC protocol; no arbitrary root path deletion API.
- Client identity validation before privileged operations.
- System-wide cache/log operations under explicit rule IDs.
- Controlled `/private/var/folders`, `/private/var/tmp` and `/private/var/log` rules.
- System application leftovers and orphan launch items.
- Time Machine local snapshot listing/thinning through supported system tooling rather than raw snapshot-file deletion.
- APFS/purgeable-space analysis and maintenance backend.

### 8E — Cleanup execution, persistence and UX

- Scan → dry-run → delete/trash/maintenance → verify state machine.
- Deletion-time revalidation of canonical path, file identity, ownership, rule and requirements.
- Safe / Review / Protected selection model.
- Ignore rules by exact path, recursive path, project, application, rule and category.
- Cleanup history/audit log without file-content capture.
- Actual reclaimed-space verification after cleanup.
- Full Disk Access/helper capability states shown explicitly instead of reporting inaccessible areas as zero bytes.
- Dedicated cleanup UI while preserving the lightweight tray overview.
- Scan cancellation and truthful progress reporting.
- Master kill switches for cleanup, privileged operations and private backends.

### 8F — Private backends and compatibility hardening

- Public API first; system CLI second; direct filesystem operations where appropriate; private/undocumented backend only where materially better.
- Private backends isolated behind capability protocols.
- Runtime symbol/capability checks; no crash when an undocumented symbol disappears.
- macOS-version/backend compatibility matrix.
- Monitoring continues to work if cleanup/helper/private backend is unavailable.

### 8G — Final verification gate

Tests are authored as part of implementation but the owner will run the final suite on the target Mac after all phases are implemented.

Required coverage includes:

- Rule and safety policy tests.
- Protected-root/path traversal tests.
- Symlink and TOCTOU replacement tests.
- Ownership and permission failure tests.
- Scanner fixture tests for every supported category.
- Application-leftover attribution tests.
- AI-model protection tests.
- Duplicate/hardlink/reclaim accounting tests.
- Similar-image classification tests.
- Helper/XPC authorization tests.
- Deletion/trash/maintenance and post-delete verification tests.
- Cancellation tests.
- Cleanup performance and no-idle-work regression tests.
- Existing MemWatch monitoring regression suite.
- Universal Release build and DMG validation.
- Physical-Mac dry-run and controlled deletion-fixture validation.

## Release definition

Phase 8 is DONE only when 8A through 8G are implemented and the final target-Mac validation passes. Intermediate branches/commits are implementation checkpoints, not product releases.
