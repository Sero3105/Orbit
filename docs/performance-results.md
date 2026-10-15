# Performance Results (same fixture, same machine)
- SystemMetrics.sample x5: 521 ms BEFORE -> 13 ms, then 3 ms AFTER (proc_listpids replaces ps spawn). ~97-99% reduction.
- Process count x5: n/a before (was inside sample) -> 0 ms (count=839-842, sane).
- dirSize 2,000 files: 12 ms -> 10-11 ms (unchanged algorithm; parallelism is at sibling level, fixture too small to show it — not claimed as a win).
- DiskScanner.scan fixture: 9 ms -> 8-10 ms (same).
- ProcessList.list: ~100 ms (unchanged; now on-demand only, off the 2s timer path).
- OrbitCheck: 8/8 PASS plus new checks (fast count sane, cancellation reports incomplete).
Remaining bottlenecks: real-home cleanup scan wall time (parallelized, not end-to-end re-measured), Processes list 100 ms per explicit load (acceptable, user-triggered), app discovery sizing on very large /Applications (parallelized).
