import SwiftUI
import OrbitCore

/// `--demo`: fictional, deterministic data for screenshots. Nothing is read from or written to the
/// real system — no sampling, scans, preferences, history or energy writes, and destructive actions are disabled.
let isDemo = CommandLine.arguments.contains("--demo")

enum Demo {
    static let user = "alex", home = "/Users/alex"
    static let GB: Int64 = 1_000_000_000, MB: Int64 = 1_000_000

    static func load(into m: Model) {
        m.metrics = Metrics(model: "Mac mini", power: "AC Power", cpu: 14.2, memUsed: 18_620 * MB, memTotal: 32_000 * MB,
                            diskFree: 412_380 * MB, diskTotal: 994_662 * MB, uptime: 275_160, battery: nil, processCount: processes.count)
        m.cpuSamples = wave(base: 12, 4, 3, 2.5, 1.3)
        m.memSamples = wave(base: 53, 1.5, 6, 0, 1)
        m.power = PowerReading(systemW: 14.6, wallW: 15.8, onBattery: false)
        m.wattSamples = wave(base: 15.6, 1.1, 2.5, 0.4, 0.9)
        m.energy = ledger()
        m.kwhPrice = 0.28
        m.history = HistoryStore(memory: history)
        m.procVM.procs = processes
        m.appsVM.apps = apps
        let c = m.cleanupVM
        c.items = cleanup.sorted { $0.size > $1.size }
        c.groups = Dictionary(grouping: c.items, by: \.category).sorted { $0.key < $1.key }
            .map { CleanupGroup(id: $0.key, title: fmtBytes($0.value.reduce(0) { $0 + $1.size }), items: $0.value) }
        c.selected = Set(c.items.filter { $0.safety == .safe }.map(\.id))
        m.maintVM.cacheInfo = "\(tr("Right now: Quick Look cache")) \(fmtBytes(48 * MB)) · \(tr("Icon cache")) \(fmtBytes(112 * MB)) · \(tr("All user caches")) \(fmtBytes(3_140 * MB))"
        m.maintVM.log = ["\(tr("QuickLook")): \(tr("exit code")) 0"]
    }

    /// 45 deterministic samples: base + a1·sin(i/p1) + a2·sin(i/p2).
    static func wave(base: Double, _ a1: Double, _ p1: Double, _ a2: Double, _ p2: Double) -> [Double] {
        (0..<45).map { (i: Int) -> Double in let x = Double(i); return base + a1 * sin(x / p1) + a2 * sin(x / p2) }
    }

    // Measured energy: ~29 days of use, today partial.
    static func ledger(now: Date = Date()) -> EnergyLedger {
        var l = EnergyLedger()
        let daily = [96.4, 138, 152, 121, 165, 144, 131, 128, 147, 156, 119, 162, 140, 133, 151, 126, 158, 137, 145, 122, 160, 149, 130, 154, 142, 136, 125, 161, 139]
        for (i, wh) in daily.enumerated() { l.add(watts: wh, seconds: 3600, at: Calendar.current.date(byAdding: .day, value: -i, to: now)!) }
        return l
    }

    static let processes: [ProcInfo] = {
        let top: [(String, String, Double, Int64)] = [
            ("Lumen Editor", user, 18.4, 1240), ("Lumen Editor Helper (Renderer)", user, 9.7, 860), ("WindowServer", "_windowserver", 7.9, 312),
            ("Tidepool Music", user, 5.2, 410), ("Kite Mail", user, 3.6, 520), ("Harbor VPN", user, 2.1, 96), ("Orbit", user, 1.8, 84),
            ("kernel_task", "root", 1.6, 46), ("Mosaic Photo", user, 1.2, 1580), ("mds_stores", "root", 0.9, 210), ("Paperboat", user, 0.8, 690),
            ("Nimbus Drive", user, 0.6, 230), ("coreaudiod", "_coreaudiod", 0.5, 28), ("Fieldnote", user, 0.4, 380), ("Waypoint Maps", user, 0.3, 270),
            ("launchd", "root", 0.2, 18), ("cfprefsd", user, 0.1, 9), ("distnoted", user, 0.1, 7), ("bluetoothd", "root", 0.1, 22), ("zsh", user, 0.0, 6)]
        let daemons = ["cloudd", "sharingd", "locationd", "powerd", "configd", "notifyd", "syslogd", "airportd", "trustd", "secd", "nsurlsessiond",
                       "rapportd", "timed", "symptomsd", "apsd", "lsd", "mdworker_shared", "opendirectoryd", "logd", "usernoted", "fontd", "coreservicesd"]
        var out = top.enumerated().map { i, t in ProcInfo(pid: Int32(400 + i * 37), cpu: t.2, memKB: t.3 * 1024, user: t.1, name: t.0) }
        for i in 0..<592 { out.append(ProcInfo(pid: Int32(1200 + i * 11), cpu: 0, memKB: Int64(2048 + (i * 7919) % 28000), user: i % 3 == 0 ? "root" : user, name: daemons[i % daemons.count])) }
        return out
    }()

    static let apps: [AppInfo] = [
        ("Atlas Notes", "com.atlaslabs.notes", "4.2.1", 312), ("Brightline", "com.brightline.app", "2.8.0", 186), ("Canvasly", "io.canvasly.desktop", "1.14.2", 645),
        ("Driftwood", "com.driftwood.reader", "3.0.4", 74), ("Ember Terminal", "dev.ember.terminal", "0.19.3", 58), ("Fieldnote", "com.fieldnote.mac", "5.1.0", 228),
        ("Harbor VPN", "net.harborvpn.client", "7.3.2", 142), ("Kite Mail", "com.kitemail.mac", "2.6.1", 418), ("Lumen Editor", "dev.lumen.editor", "1.92.0", 1210),
        ("Mosaic Photo", "com.mosaicphoto.studio", "12.4", 2840), ("Nimbus Drive", "com.nimbusdrive.sync", "9.0.7", 512), ("Orbit", "com.orbit.Orbit", "1.0.0", 3),
        ("Paperboat", "com.paperboat.docs", "3.3.0", 1060), ("Quill", "io.quill.writer", "6.2", 96), ("Tidepool Music", "com.tidepool.music", "4.7.5", 780),
        ("Waypoint Maps", "com.waypoint.maps", "2.1.0", 204),
    ].map { AppInfo(name: $0.0, path: "/Applications/\($0.0).app", bundleID: $0.1, version: $0.2, size: Int64($0.3) * MB) }

    static let cleanup: [Candidate] = {
        let rows: [(String, String, String, Int64, Safety)] = [
            ("/.cache/huggingface", "AI tool caches", "User cache dir (review each item; configs elsewhere untouched)", 2_410, .review),
            ("/.cache/pip", "AI tool caches", "User cache dir (review each item; configs elsewhere untouched)", 612, .review),
            ("/.cache/uv", "AI tool caches", "User cache dir (review each item; configs elsewhere untouched)", 388, .review),
            ("/Library/Caches/dev.lumen.editor", "App caches", "Regenerable app cache", 842, .review),
            ("/Library/Caches/Homebrew", "App caches", "Regenerable app cache", 1_120, .review),
            ("/Library/Caches/com.mosaicphoto.studio", "App caches", "Regenerable app cache", 515, .review),
            ("/Library/Caches/com.kitemail.mac", "App caches", "Regenerable app cache", 211, .review),
            ("/Library/Caches/com.tidepool.music", "App caches", "Regenerable app cache", 164, .review),
            ("/Library/Caches/com.paperboat.docs", "App caches", "Regenerable app cache", 96, .review),
            ("/Library/Logs/Paperboat", "App logs", "Log files", 48, .safe),
            ("/Library/Logs/Harbor VPN", "App logs", "Log files", 22, .safe),
            ("/Library/Logs/Lumen Editor", "App logs", "Log files", 12, .safe),
            ("/Downloads/Fieldnote-5.0.dmg", "Old installers", "Installer .dmg/.pkg older than 30 days", 182, .review),
            ("/Downloads/HarborVPN-7.2.pkg", "Old installers", "Installer .dmg/.pkg older than 30 days", 64, .review),
            ("/Library/Developer/Xcode/DerivedData/Waypoint-gxkqbzlrdyeqfh", "DerivedData", "Xcode build artifacts, regenerable", 3_200, .safe),
        ]
        return rows.enumerated().map { i, r in Candidate(path: home + r.0, category: r.1, reason: r.2, size: r.3 * MB, safety: r.4, inode: UInt64(90_000 + i)) }
    }()

    static var history: [HistoryEntry] {
        let now = Date()
        func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
        return [
            .init(date: ago(2), action: "trash", path: home + "/Library/Developer/Xcode/DerivedData/Waypoint-cpmvzhqjwlabte", result: "trashed"),
            .init(date: ago(2), action: "trash", path: home + "/Library/Logs/Brightline", result: "trashed"),
            .init(date: ago(26), action: "uninstall", path: "/Applications/Sketchpad.app", result: "trashed"),
            .init(date: ago(26), action: "uninstall", path: home + "/Library/Containers/com.sketchpad.app", result: "trashed"),
            .init(date: ago(26), action: "uninstall", path: home + "/Library/Preferences/com.sketchpad.app.plist", result: "trashed"),
            .init(date: ago(74), action: "trash", path: home + "/.cache/pip", result: "skipped: changed since scan (inode mismatch)"),
        ]
    }

    /// Synthetic app icon: rounded gradient tile with an SF Symbol, colour picked from the name.
    static func icon(_ name: String) -> NSImage {
        let palette: [(NSColor, NSColor)] = [(.systemTeal, .systemBlue), (.systemOrange, .systemPink), (.systemPurple, .systemIndigo), (.systemGreen, .systemTeal),
                                             (.systemYellow, .systemOrange), (.systemBlue, .systemPurple), (.systemPink, .systemRed), (.systemMint, .systemGreen)]
        let symbols = ["note.text", "sun.max.fill", "paintbrush.pointed.fill", "book.fill", "terminal.fill", "leaf.fill", "lock.shield.fill", "paperplane.fill",
                       "chevron.left.forwardslash.chevron.right", "photo.fill", "icloud.fill", "circle.hexagongrid", "doc.richtext.fill", "pencil.and.scribble", "music.note", "map.fill"]
        let idx = apps.firstIndex { $0.name == name } ?? abs(name.hashValue)
        let (c1, c2) = palette[idx % palette.count]
        return NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
            let tile = NSBezierPath(roundedRect: r.insetBy(dx: 4, dy: 4), xRadius: 13, yRadius: 13)
            NSGradient(starting: c1, ending: c2)?.draw(in: tile, angle: -60)
            let cfg = NSImage.SymbolConfiguration(pointSize: 26, weight: .semibold).applying(.init(paletteColors: [.white]))
            if let s = NSImage(systemSymbolName: symbols[idx % symbols.count], accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                s.draw(in: NSRect(x: (64 - s.size.width) / 2, y: (64 - s.size.height) / 2, width: s.size.width, height: s.size.height))
            }
            return true
        }
    }
}

/// App icon for the Applications screens (synthetic in demo mode).
func appIcon(_ a: AppInfo) -> NSImage { isDemo && a.bundleID != "com.orbit.Orbit" ? Demo.icon(a.name) : NSWorkspace.shared.icon(forFile: a.path) }
