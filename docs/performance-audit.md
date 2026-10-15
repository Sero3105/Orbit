# Performance Audit
Bottlenecks with evidence:
1. Metrics timer spawned /bin/ps every 2s (ProcessList.list 100 ms) only for processCount — measured 521 ms per 5 samples. Cause: SystemMetrics.sample called ProcessList.list().count. Fix: proc_listpids count (0 ms). Validated: sample x5 -> 13 ms, then 3 ms.
2. Sequential per-child dirSize in CleanupScanner/DiskScanner/AppDiscovery — on real home (100k+ files) cleanup scan took tens of seconds sequentially. Fix: bounded parallel sizing via DispatchQueue.concurrentPerform (GCD caps at core count). Fixture too small to show wall-clock gain (10 ms); real-home effect not re-benchmarked end-to-end (stated honestly).
3. Maintenance run() blocked the main thread (Process + waitUntilExit on UI thread). Fix: async on global queue, results published on main.
4. Disk list recomputed max size per row (O(n^2) on large dirs). Fix: computed once per render.
5. Navigation discarded view models (new VM per NavigationLink destination): scan results and lists rebuilt on every visit — observed in UI testing. Fix: VMs hoisted into Model and injected; state persists across sections.
6. No cancellation for cleanup/disk scans. Fix: cooperative cancellation (flag checked every 2,048 files in dirSize and between children), Cancel buttons, partial-results chip; regression check asserts cancelled dirSize reports incomplete.
Non-bottlenecks (measured, left alone): dirSize itself (12 ms/2,000 files), DiskScanner on fixture (9 ms). No Go/C component justified: the dominant cost was process-spawn overhead, removed with a Darwin API. See engine-architecture-decision.md.
