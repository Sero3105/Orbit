
if CommandLine.arguments.contains("bench") {
    func ms(_ f: () -> Void) -> Double { let t=Date(); f(); return Date().timeIntervalSince(t)*1000 }
    let root = NSTemporaryDirectory()+"orbit-bench"
    try? FileManager.default.removeItem(atPath: root)
    for d in 0..<250 { let dir=root+"/data/d\(d)"; try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories:true)
        for i in 0..<8 { try! String(repeating:"x",count:4096).write(toFile: dir+"/f\(i).bin", atomically:true, encoding:.utf8) } }
    print(String(format:"bench dirSize(2000 files): %.0f ms", ms{ _ = SafetyValidator.dirSize(URL(fileURLWithPath: root+"/data")) }))
    print(String(format:"bench DiskScanner.scan: %.0f ms", ms{ _ = DiskScanner.scan(root) }))
    print(String(format:"bench ProcessList.list: %.0f ms", ms{ _ = ProcessList.list() }))
    print(String(format:"bench Metrics.sample x5: %.0f ms", ms{ for _ in 0..<5 { _ = SystemMetrics.sample() } }))
    print(String(format:"bench processCount x5: %.0f ms (count=%d)", ms{ for _ in 0..<5 { _ = SystemMetrics.processCount() } }, SystemMetrics.processCount()))
    check(SystemMetrics.processCount() > 100, "fast process count sane")
    let (csz, ccomp) = SafetyValidator.dirSize(URL(fileURLWithPath: root+"/data"), shouldCancel: { true }); check(!ccomp, "dirSize cancellation reports incomplete")
    try? FileManager.default.removeItem(atPath: root)
    exit(0)
}
import Foundation; import OrbitCore
func check(_ c: Bool, _ n: String) { print(c ? "PASS \(n)" : "FAIL \(n)"); if !c { exit(1) } }
let tmp = NSTemporaryDirectory()+"orbit-test-\(UUID().uuidString)"
try! FileManager.default.createDirectory(atPath: tmp+"/Library/Caches/Foo", withIntermediateDirectories:true)
try! "x".write(toFile: tmp+"/Library/Caches/Foo/a.bin", atomically:true, encoding:.utf8)
let before = SafetyValidator.dirSize(URL(fileURLWithPath: tmp)).0
let scan = CleanupScanner(home: tmp).scan()
check(scan.contains{ $0.category=="App caches" }, "scan finds cache")
check(SafetyValidator.dirSize(URL(fileURLWithPath: tmp)).0 == before, "scan read-only")
let real = tmp+"/Library/Caches/Foo"; let link = tmp+"/Library/Caches/Link"
try! FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: real)
check(SafetyValidator.validate(Candidate(path:link,category:"t",reason:"t",size:1,safety:.safe,inode:SafetyValidator.inode(of:link)!), allowedRoots:[tmp]) != nil, "symlink rejected")
check(SafetyValidator.validate(Candidate(path:"/System/Library/x",category:"t",reason:"t",size:1,safety:.safe,inode:1), allowedRoots:["/"]) != nil, "protected rejected")
check(SafetyValidator.validate(Candidate(path:real,category:"t",reason:"t",size:1,safety:.safe,inode:999999), allowedRoots:[tmp]) != nil, "stale inode rejected")
check(SafetyValidator.validate(Candidate(path:real,category:"t",reason:"t",size:1,safety:.safe,inode:SafetyValidator.inode(of:real)!), allowedRoots:[tmp]) == nil, "valid accepted")
let r = TrashExecutor.run(scan, allowedRoots:[tmp], execute:false, history:nil)
check(r.allSatisfy{ $0.1.hasPrefix("Dry-run") || $0.1.hasPrefix("Skipped") } && FileManager.default.fileExists(atPath: tmp+"/Library/Caches/Foo/a.bin"), "dry-run deletes nothing")
check(!DiskScanner.scan(tmp).entries.isEmpty, "disk scan")
// Power telemetry mapping (milliwatts in, watts out)
let pr = PowerTelemetry.reading(from: ["SystemPowerIn": 7483, "AdapterEfficiencyLoss": 519, "SystemLoad": 7483])
check(pr == PowerReading(systemW: 7.483, wallW: 8.002, onBattery: false), "power reading on AC")
check(PowerTelemetry.reading(from: ["BatteryPower": 5000])?.onBattery == true && PowerTelemetry.reading(from: ["BatteryPower": 5000])?.wallW == 0, "power reading on battery")
check(PowerTelemetry.reading(from: [:]) == nil, "no telemetry -> nil, never a guess")
if let live = PowerTelemetry.read() { check(live.systemW > 0 && live.systemW < 1000, "live power sane (\(live.systemW) W)") }
// Energy ledger + cost
var led = EnergyLedger(); let now = Date()
led.add(watts: 10, seconds: 3600, at: now); led.add(watts: 20, seconds: 1800, at: Calendar.current.date(byAdding: .day, value: -3, to: now)!)
led.add(watts: -5, seconds: 100, at: now)
check(abs(led.total(days: 1, now: now) - 10) < 1e-9 && abs(led.total(days: 7, now: now) - 20) < 1e-9 && abs(led.allTime - 20) < 1e-9, "energy ledger buckets")
let ef = URL(fileURLWithPath: tmp + "/energy.json"); led.save(to: ef); check(EnergyLedger.load(from: ef) == led, "energy ledger persists")
check(abs(energyCost(wh: 2000, pricePerKWh: 0.25) - 0.5) < 1e-12, "energy cost")
// MARK: Uninstaller regression suite (audit findings)
do {
    let fm = FileManager.default, H = tmp + "/uh", L = H + "/Library/", A = H + "/Applications/"
    func dir(_ p: String) { try! fm.createDirectory(atPath: p, withIntermediateDirectories: true) }
    func file(_ p: String, _ s: String = "x") { dir((p as NSString).deletingLastPathComponent); try! s.write(toFile: p, atomically: true, encoding: .utf8) }
    func plist(_ p: String, _ d: [String: Any]) { dir((p as NSString).deletingLastPathComponent); (d as NSDictionary).write(toFile: p, atomically: true) }
    func app(_ name: String, _ id: String, helpers: [(String, String)] = []) -> String {
        let p = A + name + ".app"; plist(p + "/Contents/Info.plist", ["CFBundleIdentifier": id])
        for (rel, hid) in helpers { plist(p + "/Contents/" + rel + "/Contents/Info.plist", ["CFBundleIdentifier": hid]) }
        return p
    }
    func rel(_ a: [String]) -> Set<String> { Set(a.map { String($0.dropFirst(L.count)) }) }
    func plan(_ p: String, groups: [String: Uninstaller.Groups] = [:]) throws -> Uninstaller.Plan {
        try Uninstaller.plan(appPath: p, home: H, appRoots: [H + "/Applications"], groupsOf: { groups[($0 as NSString).lastPathComponent] ?? (nil, []) })
    }
    let byHost = "0A1B2C3D-0000-1111-2222-333344445555"

    // 1. Malicious / invalid bundle IDs are rejected outright
    for bad in ["../../Documents", "a.b/../../../Documents", "com.x/y", "..", ".com.x", "com..x", "com.x.", "nodot", "com.x y", "com.x\u{0}y", "", "com.é.x"] {
        check(!Uninstaller.isValidBundleID(bad), "bundle ID rejected: \(bad.debugDescription)")
    }
    check(["com.google.Chrome", "org.mozilla.firefox", "com.docker.docker", "ai.perplexity.mac-v3", "com.a_b.c"].allSatisfy(Uninstaller.isValidBundleID), "normal bundle IDs accepted")
    file(H + "/Documents/thesis.txt")
    let evil = app("Evil", "../../Documents")
    check((try? plan(evil)) == nil, "traversal bundle ID: no plan (\((Uninstaller.blockReason(appPath: evil, home: H, appRoots: [H + "/Applications"]) ?? "nil")))")
    // A valid app shipping a helper with a hostile ID: helper ignored
    let sneaky = app("Sneaky", "com.sneaky.app", helpers: [("Helpers/H.app", "../../../Documents"), ("Helpers/G.app", "com.sneaky.app.helper")])
    dir(L + "Caches/com.sneaky.app.helper")
    check((try? plan(sneaky))?.ownedIDs == ["com.sneaky.app", "com.sneaky.app.helper"], "hostile helper ID ignored, real helper kept")

    // 2. Chrome vs Chrome Canary: sibling data never included
    let chrome = app("Google Chrome", "com.google.Chrome", helpers: [("Frameworks/F.framework/Helpers/Google Chrome Helper.app", "com.google.Chrome.helper")])
    let canary = app("Google Chrome Canary", "com.google.Chrome.canary")
    for d in ["Application Support/com.google.Chrome", "Caches/com.google.Chrome", "Containers/com.google.Chrome.helper", "Group Containers/EQHXZ8M8AV.com.google.Chrome",
              "Caches/com.google.Chrome.canary", "Containers/com.google.Chrome.canary", "Application Support/com.google.Chrome.canary",
              "Group Containers/EQHXZ8M8AV.com.google.Chrome.canary", "Group Containers/EQHXZ8M8AV.shared", "Application Support/Google Chrome"] { dir(L + d) }
    file(L + "Preferences/com.google.Chrome.plist"); file(L + "Preferences/com.google.Chrome.canary.plist")
    file(L + "Preferences/ByHost/com.google.Chrome.\(byHost).plist"); file(L + "Preferences/ByHost/com.google.Chrome.canary.\(byHost).plist")
    file(L + "Preferences/ByHost/com.google.Chrome.cafe.plist")
    plist(L + "LaunchAgents/com.google.keystone.agent.plist", ["Label": "com.google.keystone.agent", "ProgramArguments": [chrome + "/Contents/MacOS/updater"]])
    plist(L + "LaunchAgents/com.google.Chrome.canary.agent.plist", ["Label": "com.google.Chrome.canary.agent", "Program": canary + "/Contents/MacOS/x"])
    let gg: [String: Uninstaller.Groups] = ["Google Chrome.app": ("EQHXZ8M8AV", ["EQHXZ8M8AV.com.google.Chrome", "EQHXZ8M8AV.shared", "../x", "OTHERTEAM.y"]),
                                           "Google Chrome Canary.app": ("EQHXZ8M8AV", ["EQHXZ8M8AV.com.google.Chrome.canary", "EQHXZ8M8AV.shared"])]
    let cp = try! plan(chrome, groups: gg)
    check(rel(cp.leftovers) == ["Application Support/com.google.Chrome", "Caches/com.google.Chrome", "Containers/com.google.Chrome.helper",
                                "Group Containers/EQHXZ8M8AV.com.google.Chrome", "Preferences/com.google.Chrome.plist",
                                "Preferences/ByHost/com.google.Chrome.\(byHost).plist", "LaunchAgents/com.google.keystone.agent.plist"],
          "Chrome plan: own data only (got \(rel(cp.leftovers).sorted()))")
    check(!cp.leftovers.contains { $0.contains("canary") || $0.hasSuffix("/Google Chrome") || $0.hasSuffix(".shared") }, "Chrome plan: no Canary, name-matched or shared-group data")
    check(!(try! plan(canary, groups: gg)).leftovers.contains { !$0.contains("canary") }, "Canary plan: no Chrome data")
    // A different vendor's app claiming Chrome's ID for a nested helper
    _ = app("Impostor", "com.google", helpers: [("Helpers/X.app", "com.google.Chrome")])
    check((try? plan(A + "Impostor.app"))?.ownedIDs == ["com.google"], "nested helper claiming another installed app's ID ignored")
    // Duplicate install with the same bundle ID: data is shared, only the bundle goes
    let dupe = app("Chrome Copy", "com.google.Chrome")
    let dp = try! plan(dupe, groups: gg)
    check(dp.sharedBundleID && dp.leftovers.isEmpty, "duplicate bundle ID: bundle only, no shared data")
    try! fm.removeItem(atPath: dupe)
    // Same-named app from another vendor: its folder is never matched by name
    _ = app("Notes", "com.indie.notes"); dir(L + "Application Support/Notes"); dir(L + "Caches/Notes")
    check((try! plan(A + "Notes.app")).leftovers.isEmpty, "same-named folders of other apps not matched")

    // 3. Apple and protected apps are refused
    let fakeSafari = app("Safari", "com.apple.Safari"); dir(L + "Containers/com.apple.Safari")
    check(Uninstaller.blockReason(appPath: fakeSafari, home: H, appRoots: [H + "/Applications"]) == "Apple application" && (try? plan(fakeSafari)) == nil, "Apple bundle ID refused")
    if fm.fileExists(atPath: "/Applications/Safari.app") { check((try? Uninstaller.plan(appPath: "/Applications/Safari.app")) == nil, "real Safari refused (\(Uninstaller.blockReason(appPath: "/Applications/Safari.app") ?? "nil"))") }
    try! fm.createSymbolicLink(atPath: A + "Calc.app", withDestinationPath: "/System/Applications/Calculator.app")
    check(Uninstaller.blockReason(appPath: A + "Calc.app", home: H, appRoots: [H + "/Applications"]) != nil, "symlinked app into /System refused")
    try! fm.createSymbolicLink(atPath: A + "Alias.app", withDestinationPath: A + "Notes.app")
    check(Uninstaller.blockReason(appPath: A + "Alias.app", home: H, appRoots: [H + "/Applications"]) == "application is a symbolic link", "alias to another installed app refused")
    try! fm.removeItem(atPath: A + "Alias.app")
    let outside = tmp + "/elsewhere/Thing.app"; plist(outside + "/Contents/Info.plist", ["CFBundleIdentifier": "com.thing.app"])
    check(Uninstaller.blockReason(appPath: outside, home: H, appRoots: [H + "/Applications"]) == "not in an Applications folder", "app outside Applications folders refused")
    check(Uninstaller.blockReason(appPath: A + "../Applications/Notes.app", home: H, appRoots: [H + "/Applications"]) == "invalid application path", "non-canonical app path refused")

    // 4. Symlinks: never in a plan; swapped in after preview -> skipped at execution, target intact
    let wid = app("Widget", "com.acme.widget")
    file(H + "/Precious/keep.txt"); try! fm.createSymbolicLink(atPath: L + "Caches/com.acme.widget", withDestinationPath: H + "/Precious")
    dir(L + "Logs/com.acme.widget")
    var wp = try! plan(wid)
    check(rel(wp.leftovers) == ["Logs/com.acme.widget"], "symlinked leftover excluded from plan")
    try! fm.removeItem(atPath: L + "Logs/com.acme.widget"); try! fm.createSymbolicLink(atPath: L + "Logs/com.acme.widget", withDestinationPath: H + "/Precious")
    // 5. Invalid / injected paths in the previewed list
    wp.leftovers += [L + "Caches/com.google.Chrome.canary", H + "/Documents/thesis.txt", L + "Caches/../../Documents", L + "Caches/com.acme.widget", "/etc/hosts", L + "Logs/missing.widget"]
    var trashed: [String] = []
    let fake: (URL) throws -> Void = { u in trashed.append(u.path); try fm.removeItem(at: u) }
    let wr = Uninstaller.execute(wp, home: H, appRoots: [H + "/Applications"], groupsOf: { _ in (nil, []) }, trash: fake)
    check(trashed == [wid], "only the app bundle trashed; every injected/symlinked path skipped (trashed \(trashed))")
    check(wr.dropFirst().allSatisfy { if case .skipped = $0.1 { return true }; return false }, "injected paths reported as skipped")
    check(fm.fileExists(atPath: H + "/Precious/keep.txt") && fm.fileExists(atPath: H + "/Documents/thesis.txt") && fm.fileExists(atPath: "/etc/hosts") && fm.fileExists(atPath: L + "Caches/com.google.Chrome.canary"), "symlink targets, outside files and other apps' data untouched")
    // Symlinked ~/Library subfolder: nothing under it is valid
    let H2 = tmp + "/uh2"; dir(H2 + "/Library"); dir(tmp + "/redirect/x.y"); try! fm.createSymbolicLink(atPath: H2 + "/Library/Caches", withDestinationPath: tmp + "/redirect")
    check(Uninstaller.leftoverProblem(H2 + "/Library/Caches/x.y", home: H2) == "outside allowed locations", "leftover under symlinked Library folder refused")

    // 6. Trash failure on the app bundle: stop, leave all data in place
    let mail = app("Mailer", "com.acme.mailer"); dir(L + "Caches/com.acme.mailer"); file(L + "Preferences/com.acme.mailer.plist")
    let mp = try! plan(mail); trashed = []
    let mr = Uninstaller.execute(mp, home: H, appRoots: [H + "/Applications"], groupsOf: { _ in (nil, []) }, trash: { u in if u.path == mail { throw CocoaError(.fileWriteNoPermission) }; trashed.append(u.path) })
    check(trashed.isEmpty && fm.fileExists(atPath: L + "Caches/com.acme.mailer") && fm.fileExists(atPath: L + "Preferences/com.acme.mailer.plist"), "app trash failure: no leftover touched")
    check(mr.first.map { if case .failed = $0.1 { return true }; return false } == true && mr.dropFirst().allSatisfy { $0.1 == .skipped("application could not be moved to Trash") }, "app trash failure reported")
    // App swapped for a different bundle between preview and confirm
    plist(mail + "/Contents/Info.plist", ["CFBundleIdentifier": "com.other.thing"]); trashed = []
    _ = Uninstaller.execute(mp, home: H, appRoots: [H + "/Applications"], groupsOf: { _ in (nil, []) }, trash: fake)
    check(trashed.isEmpty, "app changed since preview: nothing trashed")

    // Helper with a valid but foreign ID (not "<id>.…") inside the bundle: never owned
    let host = app("Host", "com.host.app", helpers: [("Helpers/V.app", "com.victim.app")]); dir(L + "Caches/com.victim.app")
    check((try! plan(host)).leftovers.isEmpty, "foreign-ID helper inside bundle not treated as owned")
    // Direct path validator
    dir(L + "Caches/real.item")
    check(Uninstaller.leftoverProblem(L + "Caches/real.item", home: H) == nil, "validator accepts a real owned path")
    check(Uninstaller.leftoverProblem(L + "Caches/com.acme.widget", home: H) == "symbolic link", "validator rejects symlink")
    check(Uninstaller.leftoverProblem(H + "/Documents/thesis.txt", home: H) == "outside allowed locations", "validator rejects outside path")
    check(Uninstaller.leftoverProblem(L + "Caches/./real.item", home: H) == "invalid path", "validator rejects non-canonical path")
    // TOCTOU: leftover swapped for a symlink after the recheck plan, while the app is being trashed
    let race = app("Racer", "com.acme.racer"); dir(L + "Caches/com.acme.racer")
    let rp = try! plan(race); trashed = []
    _ = Uninstaller.execute(rp, home: H, appRoots: [H + "/Applications"], groupsOf: { _ in (nil, []) }, trash: { u in
        if u.path == race { try! fm.removeItem(atPath: L + "Caches/com.acme.racer"); try! fm.createSymbolicLink(atPath: L + "Caches/com.acme.racer", withDestinationPath: H + "/Precious") }
        trashed.append(u.path) })
    check(trashed == [race] && fm.fileExists(atPath: H + "/Precious/keep.txt"), "leftover swapped to symlink mid-operation: skipped")

    // 7. Happy path: everything previewed and still owned goes, nothing else
    let ok = app("Okay", "com.acme.okay", helpers: [("Library/LoginItems/OkayHelper.app", "com.acme.okay.helper")])
    for d in ["Application Support/com.acme.okay", "Containers/com.acme.okay.helper", "Caches/com.acme.okayish"] { dir(L + d) }
    file(L + "Saved Application State/com.acme.okay.savedState/x"); file(L + "Cookies/com.acme.okay.binarycookies")
    let op = try! plan(ok); trashed = []
    let or = Uninstaller.execute(op, home: H, appRoots: [H + "/Applications"], groupsOf: { _ in (nil, []) }, trash: fake)
    check(or.allSatisfy { $0.1 == .trashed } && Set(trashed) == Set([ok] + op.leftovers) && op.leftovers.count == 4, "happy path: app + 4 owned items trashed")
    check(fm.fileExists(atPath: L + "Caches/com.acme.okayish"), "look-alike ID (okayish) untouched")
}
try? FileManager.default.removeItem(atPath: tmp); print("ALL PASS")
