
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
// Uninstall leftovers: every standard location, exact matches only
let fh = tmp + "/home", id = "com.acme.Widget"
for p in ["Library/Application Support/\(id)", "Library/Application Support/Widget", "Library/Caches/\(id)", "Library/Containers/\(id)", "Library/Containers/\(id).helper",
          "Library/Group Containers/ABCDE12345.\(id)", "Library/HTTPStorages/\(id)", "Library/WebKit/\(id)", "Library/Logs/Widget",
          "Library/Application Support/com.acme.WidgetPro", "Library/Containers/com.acme.Other", "Library/Application Support/Acme"] {
    try! FileManager.default.createDirectory(atPath: fh + "/" + p, withIntermediateDirectories: true) }
try! FileManager.default.createDirectory(atPath: fh + "/Library/Preferences/ByHost", withIntermediateDirectories: true)
try! FileManager.default.createDirectory(atPath: fh + "/Library/LaunchAgents", withIntermediateDirectories: true)
for p in ["Library/Preferences/\(id).plist", "Library/Preferences/ByHost/\(id).0000-1111.plist", "Library/LaunchAgents/\(id).updater.plist", "Library/Preferences/com.acme.WidgetPro.plist"] {
    try! "x".write(toFile: fh + "/" + p, atomically: true, encoding: .utf8) }
let lo = Set(AppDiscovery.leftovers(bundleID: id, appName: "Widget", home: fh).map { String($0.dropFirst(fh.count + 1)) })
check(lo == ["Library/Application Support/\(id)", "Library/Application Support/Widget", "Library/Caches/\(id)", "Library/Containers/\(id)", "Library/Containers/\(id).helper",
             "Library/Group Containers/ABCDE12345.\(id)", "Library/HTTPStorages/\(id)", "Library/WebKit/\(id)", "Library/Logs/Widget",
             "Library/Preferences/\(id).plist", "Library/Preferences/ByHost/\(id).0000-1111.plist", "Library/LaunchAgents/\(id).updater.plist"], "leftovers: complete and exact (got \(lo.sorted()))")
check(AppDiscovery.leftovers(bundleID: "—", home: fh).isEmpty, "leftovers: no bundle ID -> nothing")
try? FileManager.default.removeItem(atPath: tmp); print("ALL PASS")
