# Bug Audit
Observed/reproduced:
B1 ProcessList pipe deadlock (found session 1 via sample): waitUntilExit before reading pipe hung app startup when ps output exceeded pipe buffer. Fixed earlier (read before wait), regression-covered by app launching + bench.
B2 Scan results and lists lost on navigation (new VM per view) — observed during UI verification. Fixed by hoisting VMs.
B3 Maintenance tasks froze UI (synchronous Process on main thread) — code inspection + known pattern. Fixed async.
B4 Blank screens during Disk/Apps/Processes loading (screenshot review) — fixed with loading states in previous round; retained.
B5 Metrics staleness cost: dashboard process count required full ps parse every 2s — fixed via proc_listpids.
B6 Disk row O(n^2) max recomputation — code inspection. Fixed.
Not reproduced / not claimed: crashes (none observed; no .ips), permission-failure mishandling (errors surface as partial-scan flags and per-item results).
Fixes verified: OrbitCheck 8/8 PASS after changes; bench Metrics.sample x5 521 ms -> 3-13 ms; app relaunched and screenshot-verified after reinstall.
