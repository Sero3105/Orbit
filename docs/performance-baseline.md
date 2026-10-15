# Performance Baseline (2026-10-15, this Mac, arm64)
Method: `swift run -c release OrbitCheck bench` — controlled fixture of 2,000 files / 250 dirs in /tmp, real process table (~840 processes), best single run (workload identical before/after).
BEFORE optimization:
- dirSize (2,000 files): 12 ms
- DiskScanner.scan (fixture root): 9 ms
- ProcessList.list (spawn /bin/ps + parse): 100 ms
- SystemMetrics.sample x5: 521 ms (~104 ms/sample) — dominated by spawning ps on every 2s timer tick just to count processes.
App memory: not measured with Instruments (unavailable without Xcode); footprint via sample(1) on running app was ~3 MB physical during idle earlier (not a controlled metric, not claimed as benchmark).
Startup: not measured with a controlled harness; GUI launch-to-window observed 5-6s via `open` + window polling, not reported as a benchmark.
