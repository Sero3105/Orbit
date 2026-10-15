# Feature Specification
Dashboard: real CPU/memory/disk/uptime/battery/process count (native APIs; unavailable = "Unavailable", never simulated).
Cleanup: scan ~/Library/Caches, ~/Library/Logs, ~/Downloads installers (>30d), Xcode DerivedData, AI-tool caches (~/.cache etc.). Classify Safe/Review/Protected. Review-first: select -> confirm sheet -> revalidate -> Trash -> report+history. Dry-run = scan itself.
Disk: scan folder, sizes, breadcrumb, sort, bar visualization, reveal in Finder, Trash with separate confirm. Partial scans flagged.
Apps: list /Applications+~/Applications (name, bundle id, version, size), leftover lookup by bundle id, uninstall = preview + confirm + Trash app & selected leftovers only.
Maintenance (user-level, fixed args): refresh QuickLook cache (qlmanage -r), flush DNS cache (dscacheutil), report exit status. No sudo, no SIP/TCC bypass.
Processes: ps listing, sort/filter, terminate non-system process only after confirm.
Menu bar: CPU/memory compact panel, open main window.
Not implemented: privileged cleanup, fan/temperature (no public API without helpers — shown Unavailable), app update checks (no reliable source), auto login item (preference shown, not installed).
