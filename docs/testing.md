# Testing

XCTest is not available with a Command Line Tools-only toolchain, so tests live in an executable check suite: `Sources/OrbitCheck`.

```bash
swift run OrbitCheck          # full check suite (prints PASS/FAIL per check, exits non-zero on failure)
swift run OrbitCheck bench    # timings on a generated fixture (results depend on the machine)
```

All checks run against temporary fixtures created under `NSTemporaryDirectory()`; nothing in the real home folder is scanned for changes or moved to Trash. Trash operations in tests use an injected closure instead of the real Trash.

## What is covered
- **Cleanup** — scanning is read-only; revalidation rejects symlinks, protected system paths, stale inodes and paths outside the allowed roots; dry-run deletes nothing.
- **Disk Analyzer** — inodes recorded at scan time; Move to Trash only inside the home folder, never the home itself, its standard folders or `~/Library` and its direct subfolders; rejects symlinks (including a symlinked parent), non-canonical and missing paths, items swapped since the scan; errors are reported and every outcome is recorded in History.
- **Uninstaller** — strict bundle-ID validation (path traversal and other malformed IDs), no data from look-alike apps (e.g. Chrome vs Chrome Canary), helpers only when nested and prefixed, shared/foreign group containers excluded, Apple and symlinked apps refused, every path revalidated before trashing, nothing touched when the app bundle cannot be trashed.
- **Energy** — power telemetry mapping, energy ledger buckets and persistence, cost math.
- **Metrics** — process count sanity, cancellation of directory sizing.

Security-relevant guards are mutation-tested: disabling any of them makes at least one check fail.

## Not covered automatically
- UI rendering and interaction (use `Orbit --demo --screenshots <dir>` to render every section with fictional data and inspect the images).
- Destructive flows on real user data — deliberately never exercised.
- Gatekeeper behaviour on other Macs (the app is ad-hoc signed and not notarized).
