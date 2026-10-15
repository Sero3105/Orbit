# Orbit Architecture
OrbitCore (library, testable, no UI): SafetyValidator, CleanupScanner, DiskScanner, AppDiscovery, SystemMetrics, ProcessList, HistoryStore.
Orbit (SwiftUI app): Dashboard, Cleanup, Disk, Apps, Maintenance, Processes, Settings, MenuBarExtra. Views call OrbitCore only.
Safety: scan never mutates; execution revalidates inode+path+root allowlist, refuses symlinks/protected/system paths, moves to Trash (recoverable), logs every op to ~/Library/Application Support/Orbit/history.json. Settings in UserDefaults (app bundle id scope).
Privileged ops: none. DNS flush etc. run as user with fixed-arg Process; failures reported honestly.
