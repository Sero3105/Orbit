# Testing
swift test (temp-dir fixtures: scan read-only, symlink rejection, inode revalidation, protected paths, disk sizes, partial scan). Manual: launch installed app, check dashboard/cleanup/disk read-only flows. No destructive test on real data.

## Verification report (2026-10-15)
- Build: `swift build -c release` OK (CLT Swift 6.4, no Xcode; XCTest unavailable -> OrbitCheck executable suite used).
- OrbitCheck: 8/8 PASS (scan finds cache, scan read-only, symlink rejected, protected rejected, stale inode rejected, valid accepted, dry-run deletes nothing, disk scan).
- Package: scripts/package.sh built build/Orbit.app, ad-hoc codesign --verify --deep --strict OK, installed /Applications/Orbit.app (820K, com.orbit.Orbit 1.0.0).
- Launch: installed app running (launchd parent), main window 900x612 present via CGWindowList, main thread idle in NSApplication run loop (sample), ~/Library/Application Support/Orbit/ created.
- Bug found+fixed during verification: ProcessList pipe deadlock (waitUntilExit before reading pipe) blocked Model.init; fixed to read before wait, reinstalled, re-verified.
- Not verified: pixel/screenshot check (screencapture denied in this session: "could not create image from display"), destructive flows on real data (by design — only temp fixtures + Trash semantics in code), Gatekeeper on other Macs (ad-hoc signature).

## UI verification via screenshots (2026-10-15, installed app)
- Dashboard: VERIFIED visually, multiple frames with changing values (CPU 21.8%->7.9%->20%, Memory ~13-14.9/25.77 GB, Disk 332.6 GB free, Processes 804-833, Uptime 3h30-3h36, Battery/Temp/Fan/GPU "Unavailable" as designed).
- Disk Analyzer: VERIFIED visually (home listing, real sizes sorted desc, Reveal/Open/Trash buttons, breadcrumb path).
- Cleanup scan: VERIFIED visually in real UI (111 candidates, 8.1 GB; AI caches codex-runtimes 3.46 GB, uv 2.59 GB, huggingface 1.46 GB; all "review", none pre-selected).
- Cleanup select/confirm/Trash, Applications uninstall, Maintenance, Processes terminate, Settings, menu-bar panel: NOT driven end-to-end in this session. Synthetic CGEvent input across dual displays with another fullscreen app stealing frontmost proved unreliable (sidebar navigation worked; button activation intermittent; stray clicks risked hitting other apps, so blind input was stopped). Destructive flows were deliberately not executed on real user data; they are covered by OrbitCheck temp-fixture tests (dry-run, revalidation, symlink/protected rejection) and code review.
- No crash reports for Orbit; observed terminations were clean (window close -> terminate), no .ips generated.
