# Orbit — Your Mac, in balance.

Independent native macOS maintenance app (Swift/SwiftUI, no dependencies), inspired by Mole's observable feature set. No Mole code or assets used (Mole CLI is GPL-3.0; Orbit is a clean-room implementation).

## Features
- **Dashboard**: real CPU, memory, disk, battery, uptime, process count via native APIs. Temperature/fan/GPU shown as Unavailable (no public API without a privileged helper) — never simulated.
- **Cleanup**: read-only scan of app caches, logs (>7d), old installers in Downloads (>30d), Xcode DerivedData, `~/.cache`. Review-first: select → confirm → revalidate (inode, symlink, protected-path, allowed-root checks) → move to Trash. Results + history reported per item.
- **Disk Analyzer**: folder sizes, breadcrumb navigation, sort/filter, partial-scan flagging, Reveal in Finder, Trash with separate confirmation.
- **Applications**: installed apps with bundle ID/version/size; leftovers matched by exact bundle ID only; uninstall = preview + confirm + Trash.
- **Maintenance**: user-level QuickLook cache refresh, DNS flush, icon-services refresh — fixed-argument processes, exit status reported. No sudo.
- **Processes**: live list, filter, terminate own non-system processes only after confirmation (SIGTERM).
- **Menu bar**: CPU/memory/disk summary, open/quit.
- **History**: local log at `~/Library/Application Support/Orbit/history.json` (max 500).

## Safety
Scan never modifies anything. No sudo, no privileged helper, no SIP/TCC bypass, no telemetry/network, no shell strings from UI input. Deletion is always Trash (recoverable) after explicit confirmation and revalidation. See [docs/security-model.md](docs/security-model.md).

## Build & install
Requires Swift toolchain (Command Line Tools is enough; Xcode not required).
```bash
./scripts/package.sh        # builds, runs OrbitCheck, assembles + ad-hoc signs, installs to /Applications/Orbit.app
INSTALL=0 ./scripts/package.sh   # build only, to build/Orbit.app
swift run OrbitCheck        # safety/scan self-checks (temp fixtures only)
```
Note: XCTest is unavailable with CLT-only installs, so tests are an executable check suite (`Sources/OrbitCheck`) with the same assertions.

## Locations
- Installed app: `/Applications/Orbit.app` (bundle `com.orbit.Orbit`, min macOS 14, arm64 as built)
- History: `~/Library/Application Support/Orbit/history.json`
- Uninstall Orbit: drag `/Applications/Orbit.app` to Trash; history file remains unless you delete it manually.

## Limitations
No privileged cleanup, no fan/temperature/GPU, no app-update checks (no reliable source integrated — not claimed), dashboard refresh fixed at 2s, ad-hoc signature (Gatekeeper may require right-click → Open on other Macs).
