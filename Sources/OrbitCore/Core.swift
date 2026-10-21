import Foundation
#if canImport(Darwin)
import Darwin
import IOKit.ps
#endif

public enum Safety: String, Codable, CaseIterable { case safe, review, protected_ = "protected" }
public struct Candidate: Identifiable, Codable, Hashable {
    public var id: String { path }
    public var path: String; public var category: String; public var reason: String
    public var size: Int64; public var safety: Safety; public var inode: UInt64; public var modified: Date?
    public init(path:String,category:String,reason:String,size:Int64,safety:Safety,inode:UInt64,modified:Date?=nil){self.path=path;self.category=category;self.reason=reason;self.size=size;self.safety=safety;self.inode=inode;self.modified=modified}
}

public enum SafetyValidator {
    public static let protectedPrefixes = ["/System","/usr","/bin","/sbin","/Library/Apple","/Applications","/Volumes"]
    public static func inode(of path: String) -> UInt64? { var s=stat(); guard stat(path,&s)==0 else { return nil }; return UInt64(s.st_ino) }
    /// Revalidate before delete: exists, same inode, not symlink, under an allowed root, not protected.
    public static func validate(_ c: Candidate, allowedRoots: [String]) -> String? {
        if c.safety == .protected_ { return "protected classification" }
        var st = stat(); guard stat(c.path,&st)==0 else { return "missing" }
        if UInt64(st.st_ino) != c.inode { return "changed since scan (inode mismatch)" }
        var lst = stat(); _ = lstat(c.path,&lst)
        if (lst.st_mode & S_IFMT) == S_IFLNK { return "symlink — skipped" }
        let p = (c.path as NSString).standardizingPath
        for pre in protectedPrefixes where p == pre || p.hasPrefix(pre + "/") { return "protected system path" }
        guard allowedRoots.contains(where: { p == $0 || p.hasPrefix(($0 as NSString).standardizingPath + "/") }) else { return "outside allowed roots" }
        if p.split(separator: "/").count < 3 { return "too shallow" }
        return nil
    }
    public static func dirSize(_ url: URL, shouldCancel: () -> Bool = { false }) -> (Int64, Bool) { // (bytes, complete)
        var total: Int64 = 0; var complete = true; var seen = 0
        guard let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey,.fileSizeKey,.isRegularFileKey], options: []) else { return (0,false) }
        for case let f as URL in en {
            seen += 1; if seen % 2048 == 0 && shouldCancel() { return (total, false) }
            do { let v = try f.resourceValues(forKeys: [.totalFileAllocatedSizeKey,.fileSizeKey,.isRegularFileKey]); if v.isRegularFile == true { total += Int64(v.totalFileAllocatedSize ?? v.fileSize ?? 0) } }
            catch { complete = false }
        }
        return (total, complete)
    }
    /// Bounded parallel sizing of sibling paths (GCD caps concurrency at core count).
    public static func parallelSizes(_ paths: [String], shouldCancel: () -> Bool = { false }) -> [Int64] {
        var out = [Int64](repeating: 0, count: paths.count)
        out.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: paths.count) { i in
                if shouldCancel() { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: paths[i], isDirectory: &isDir) else { return }
                buf[i] = isDir.boolValue ? dirSize(URL(fileURLWithPath: paths[i]), shouldCancel: shouldCancel).0
                    : ((try? FileManager.default.attributesOfItem(atPath: paths[i]))?[.size] as? NSNumber)?.int64Value ?? 0
            }
        }
        return out
    }
}

public struct CleanupScanner {
    public var home: String; public init(home: String = NSHomeDirectory()) { self.home = home }
    public struct Category { public var name:String; public var root:String; public var reason:String; public var safety:Safety; public var minAgeDays: Double
        public init(name:String,root:String,reason:String,safety:Safety,minAgeDays:Double){self.name=name;self.root=root;self.reason=reason;self.safety=safety;self.minAgeDays=minAgeDays} }
    public func categories() -> [Category] {
        let h = home
        return [
            .init(name:"App caches", root:"\(h)/Library/Caches", reason:"Regenerable app cache", safety:.review, minAgeDays:0),
            .init(name:"App logs", root:"\(h)/Library/Logs", reason:"Log files", safety:.safe, minAgeDays:7),
            .init(name:"Old installers", root:"\(h)/Downloads", reason:"Installer .dmg/.pkg older than 30 days", safety:.review, minAgeDays:30),
            .init(name:"DerivedData", root:"\(h)/Library/Developer/Xcode/DerivedData", reason:"Xcode build artifacts, regenerable", safety:.safe, minAgeDays:0),
            .init(name:"AI tool caches", root:"\(h)/.cache", reason:"User cache dir (review each item; configs elsewhere untouched)", safety:.review, minAgeDays:0),
        ]
    }
    /// Read-only scan. Direct children of each root become candidates (installers: matching files only).
    public func scan(shouldCancel: () -> Bool = { false }) -> [Candidate] {
        var out: [Candidate] = []
        let fm = FileManager.default; let now = Date()
        for cat in categories() {
            if shouldCancel() { break }
            guard let kids = try? fm.contentsOfDirectory(atPath: cat.root) else { continue }
            let kidPaths = kids.sorted().map { (cat.root as NSString).appendingPathComponent($0) }
            let kidSizes = SafetyValidator.parallelSizes(kidPaths, shouldCancel: shouldCancel)
            for (idx, k) in kids.sorted().enumerated() {
                let p = (cat.root as NSString).appendingPathComponent(k)
                if cat.name == "Old installers" { guard [".dmg",".pkg"].contains((p as NSString).pathExtension.lowercased().withDot) else { continue } }
                let attrs = try? fm.attributesOfItem(atPath: p)
                let mod = attrs?[.modificationDate] as? Date
                if let m = mod, now.timeIntervalSince(m) < cat.minAgeDays * 86400 { continue }
                var isDir: ObjCBool = false; guard fm.fileExists(atPath: p, isDirectory: &isDir) else { continue }
                let sz = kidSizes[idx]
                guard sz > 0, let ino = SafetyValidator.inode(of: p) else { continue }
                out.append(Candidate(path:p, category:cat.name, reason:cat.reason, size:sz, safety:cat.safety, inode:ino, modified:mod))
            }
        }
        return out.sorted { $0.size > $1.size }
    }
}
extension String { var withDot: String { hasPrefix(".") ? self : "." + self } }

public struct DiskEntry: Identifiable, Hashable { public var id:String{path}; public var name:String; public var path:String; public var size:Int64; public var isDir:Bool; public var complete:Bool; public var inode:UInt64
    public init(name:String,path:String,size:Int64,isDir:Bool,complete:Bool,inode:UInt64=0){self.name=name;self.path=path;self.size=size;self.isDir=isDir;self.complete=complete;self.inode=inode} }
public enum DiskScanner {
    public static func scan(_ dir: String, shouldCancel: () -> Bool = { false }) -> (entries:[DiskEntry], complete:Bool) {
        let fm = FileManager.default; let allComplete = true; var out:[DiskEntry]=[]
        let names = (try? fm.contentsOfDirectory(atPath: dir))?.sorted() ?? []
        let paths = names.map { (dir as NSString).appendingPathComponent($0) }
        let sizes = SafetyValidator.parallelSizes(paths, shouldCancel: shouldCancel)
        for (i,k) in names.enumerated() {
            var isDir: ObjCBool=false; guard fm.fileExists(atPath:paths[i],isDirectory:&isDir) else { continue }
            var st = stat(); let ino = lstat(paths[i], &st) == 0 ? UInt64(st.st_ino) : 0
            out.append(.init(name:k,path:paths[i],size:sizes[i],isDir:isDir.boolValue,complete:!shouldCancel(),inode:ino))
        }
        return (out.sorted{$0.size>$1.size}, allComplete && !shouldCancel())
    }
}

/// Disk Analyzer "Move to Trash": only items inside the home folder, never the home itself, its standard
/// top-level folders, ~/Library or its macOS-owned direct subfolders. Third-party ~/Library folders (Android,
/// Google, …) may be trashed. Revalidated right before the move; every outcome is recorded.
public enum DiskTrash {
    static let protectedHomeFolders: Set<String> = ["Library", "Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications", ".Trash"]
    /// ~/Library subfolders created or used by macOS itself; anything starting with "com.apple" or "." is also protected.
    static let systemLibraryFolders: Set<String> = [
        "Accessibility", "Accounts", "Apple", "AppleMediaServices", "Application Scripts", "Application Support", "Assistant", "Assistants",
        "Audio", "Autosave Information", "Biome", "Caches", "Calendars", "CallServices", "CloudStorage", "ColorPickers", "ColorSync", "Colors",
        "Compositions", "Contacts", "ContainerManager", "Containers", "Cookies", "CoreData", "CoreFollowUp", "DES", "Daemon Containers",
        "DataAccess", "DataDeliveryServices", "Developer", "Dictionaries", "DoNotDisturb", "DuetExpertCenter", "Favorites", "FileProvider",
        "Finance", "FinanceBackup", "FontCollections", "Fonts", "FrontBoard", "GameKit", "Group Containers", "HTTPStorages", "HomeKit",
        "IdentityServices", "Input Methods", "IntelligencePlatform", "Intents", "Internet Plug-Ins", "Keyboard", "Keyboard Layouts",
        "KeyboardServices", "Keychains", "LanguageModeling", "LaunchAgents", "LockdownMode", "Logs", "Mail", "Maps", "MediaAnalysis",
        "Messages", "Metadata", "Mobile Documents", "News", "PDF Services", "PPM", "Passes", "PersonalizationPortrait", "Photos",
        "PreferencePanes", "Preferences", "Printers", "PrivateCloudCompute", "QuickLook", "Reminders", "ResponseKit", "Safari",
        "SafariSafeBrowsing", "SafariSandboxBroker", "Saved Application State", "Screen Savers", "Scripts", "Services", "Sharing",
        "Shortcuts", "Sounds", "Speech", "Spelling", "Spotlight", "StatusKit", "Suggestions", "SyncedPreferences", "Translation", "Trial",
        "UnifiedAssetFramework", "Weather", "WebKit", "Workflows",
    ]
    static func isSystemLibraryFolder(_ name: String) -> Bool {
        systemLibraryFolders.contains(name) || name.hasPrefix("com.apple") || name.hasPrefix(".")
    }

    /// nil when `path` may be trashed now.
    public static func problem(_ path: String, inode: UInt64, home: String = NSHomeDirectory()) -> String? {
        guard !path.contains("\0"), path.hasPrefix("/"), (path as NSString).standardizingPath == path else { return "invalid path" }
        var st = stat(); guard lstat(path, &st) == 0 else { return "missing" }
        if (st.st_mode & S_IFMT) == S_IFLNK { return "symlink — skipped" }
        if UInt64(st.st_ino) != inode { return "changed since scan (inode mismatch)" }
        guard path.hasPrefix(home + "/"), let realHome = Uninstaller.realpath(home), let real = Uninstaller.realpath(path),
              real == realHome + path.dropFirst(home.count) else { return "outside allowed roots" }  // also catches a symlink in any parent
        let rel = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        if (rel.count == 1 && protectedHomeFolders.contains(rel[0])) || (rel.first == "Library" && (rel.count == 1 || (rel.count == 2 && isSystemLibraryFolder(rel[1])))) { return "protected system path" }
        for pre in SafetyValidator.protectedPrefixes where real == pre || real.hasPrefix(pre + "/") { return "protected system path" }
        return nil
    }

    /// Validate, move to Trash, record the outcome. Returns "Moved to Trash", "Skipped: <why>" or "Failed: <error>".
    @discardableResult
    public static func run(_ e: DiskEntry, home: String = NSHomeDirectory(), history: HistoryStore?,
                           trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> String {
        if let why = problem(e.path, inode: e.inode, home: home) {
            history?.add(.init(date: Date(), action: "trash", path: e.path, result: "skipped: \(why)")); return "Skipped: \(why)"
        }
        do { try trash(URL(fileURLWithPath: e.path)); history?.add(.init(date: Date(), action: "trash", path: e.path, result: "trashed")); return "Moved to Trash" }
        catch { history?.add(.init(date: Date(), action: "trash", path: e.path, result: "failed: \(error.localizedDescription)")); return "Failed: \(error.localizedDescription)" }
    }
}

public struct AppInfo: Identifiable, Hashable { public var id:String{bundleID+path}; public var name:String; public var path:String; public var bundleID:String; public var version:String; public var size:Int64
    public init(name:String,path:String,bundleID:String,version:String,size:Int64){self.name=name;self.path=path;self.bundleID=bundleID;self.version=version;self.size=size} }
public enum AppDiscovery {
    public static func apps(extraRoots:[String]=[]) -> [AppInfo] {
        let roots = ["/Applications", NSHomeDirectory()+"/Applications"] + extraRoots; var out:[AppInfo]=[]
        var paths:[String]=[]
        for r in roots { for k in (try? FileManager.default.contentsOfDirectory(atPath:r)) ?? [] where k.hasSuffix(".app") { paths.append((r as NSString).appendingPathComponent(k)) } }
        let sizes = SafetyValidator.parallelSizes(paths)
        for (i,p) in paths.enumerated() { let b=Bundle(path:p); let k=(p as NSString).lastPathComponent
            out.append(.init(name:(k as NSString).deletingPathExtension, path:p, bundleID:b?.bundleIdentifier ?? "—", version:(b?.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—", size:sizes[i])) }
        return out.sorted{$0.name.lowercased()<$1.name.lowercased()}
    }
}

public struct Metrics { public var model:String = ""; public var power:String = ""; public var cpu:Double; public var memUsed:Int64; public var memTotal:Int64; public var diskFree:Int64; public var diskTotal:Int64; public var uptime:TimeInterval; public var battery:Int?; public var processCount:Int
    public init(model:String, power:String, cpu:Double, memUsed:Int64, memTotal:Int64, diskFree:Int64, diskTotal:Int64, uptime:TimeInterval, battery:Int?, processCount:Int) { self.model=model; self.power=power; self.cpu=cpu; self.memUsed=memUsed; self.memTotal=memTotal; self.diskFree=diskFree; self.diskTotal=diskTotal; self.uptime=uptime; self.battery=battery; self.processCount=processCount } }
public enum SystemMetrics {
    public static func processCount() -> Int {
        let n = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard n > 0 else { return 0 }
        return Int(n) / MemoryLayout<Int32>.size
    }
    static var lastCPU: (user:UInt64,sys:UInt64,idle:UInt64,nice:UInt64)?
    public static func sample() -> Metrics {
        var cpu = 0.0
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let kr = withUnsafeMutablePointer(to:&info){ $0.withMemoryRebound(to:integer_t.self, capacity:Int(count)){ host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        if kr == KERN_SUCCESS {
            let cur=(UInt64(info.cpu_ticks.0),UInt64(info.cpu_ticks.1),UInt64(info.cpu_ticks.2),UInt64(info.cpu_ticks.3))
            if let l=lastCPU { let du=cur.0-l.user,ds=cur.1-l.sys,di=cur.2-l.idle,dn=cur.3-l.nice; let tot=du+ds+di+dn; if tot>0 { cpu=Double(du+ds+dn)/Double(tot)*100 } }
            lastCPU=cur
        }
        var vm = vm_statistics64(); var vc = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size/MemoryLayout<integer_t>.size)
        let vmkr = withUnsafeMutablePointer(to:&vm){ $0.withMemoryRebound(to:integer_t.self, capacity:Int(vc)){ host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vc) } }
        let page = Int64(vm_kernel_page_size); var total:Int64=0; var sz=MemoryLayout<Int64>.size
        sysctlbyname("hw.memsize",&total,&sz,nil,0)
        let used = vmkr==KERN_SUCCESS ? (Int64(vm.active_count)+Int64(vm.wire_count)+Int64(vm.compressor_page_count))*page : 0
        let vals = try? URL(fileURLWithPath:"/").resourceValues(forKeys:[.volumeAvailableCapacityKey,.volumeTotalCapacityKey])
        var batt: Int? = nil
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for src in list { if let d = IOPSGetPowerSourceDescription(blob, src)?.takeUnretainedValue() as? [String:Any], let pct = d[kIOPSCurrentCapacityKey as String] as? Int { batt = pct } }
        }
        var modelBuf = [CChar](repeating: 0, count: 128); var msz = 128; sysctlbyname("hw.model", &modelBuf, &msz, nil, 0)
        return Metrics(model: String(cString: modelBuf), power: batt != nil ? "Battery" : "AC Power", cpu:cpu, memUsed:used, memTotal:total, diskFree:Int64(vals?.volumeAvailableCapacity ?? 0), diskTotal:Int64(vals?.volumeTotalCapacity ?? 0), uptime:ProcessInfo.processInfo.systemUptime, battery:batt, processCount:SystemMetrics.processCount())
    }
}

public struct ProcInfo: Identifiable, Hashable { public var id:Int32{pid}; public var pid:Int32; public var cpu:Double; public var memKB:Int64; public var user:String; public var name:String
    public init(pid:Int32,cpu:Double,memKB:Int64,user:String,name:String){self.pid=pid;self.cpu=cpu;self.memKB=memKB;self.user=user;self.name=name} }
public enum ProcessList {
    public static func list() -> [ProcInfo] {
        var p = Process(); p.executableURL = URL(fileURLWithPath:"/bin/ps"); p.arguments=["-axo","pid=,%cpu=,rss=,user=,comm="]
        let pipe=Pipe(); p.standardOutput=pipe; guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        let s = String(data:data, encoding:.utf8) ?? ""
        return s.split(separator:"\n").compactMap{ line in
            let f=line.split(separator:" ", maxSplits:4, omittingEmptySubsequences:true); guard f.count==5, let pid=Int32(f[0]) else { return nil }
            return ProcInfo(pid:pid, cpu:Double(f[1]) ?? 0, memKB:Int64(f[2]) ?? 0, user:String(f[3]), name:(f[4].trimmingCharacters(in:.whitespaces) as NSString).lastPathComponent)
        }
    }
    @discardableResult public static func terminate(pid:Int32) -> Bool { kill(pid, SIGTERM) == 0 }
}

public struct HistoryEntry: Codable, Identifiable { public var id=UUID(); public var date:Date; public var action:String; public var path:String; public var result:String
    public init(date:Date,action:String,path:String,result:String){self.date=date;self.action=action;self.path=path;self.result=result} }
public final class HistoryStore {
    public var file: URL; public private(set) var entries:[HistoryEntry]=[]
    public init() { let d=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Orbit",isDirectory:true); try? FileManager.default.createDirectory(at:d,withIntermediateDirectories:true); file=d.appendingPathComponent("history.json"); load() }
    /// In-memory store (demo/screenshots): never reads or writes the history file.
    public init(memory e:[HistoryEntry]) { file = URL(fileURLWithPath: "/dev/null"); entries = e }
    public func load(){ if let data=try? Data(contentsOf:file), let e=try? JSONDecoder().decode([HistoryEntry].self,from:data){ entries=e } }
    public func add(_ e:HistoryEntry){ entries.insert(e,at:0); entries=Array(entries.prefix(500)); guard file.path != "/dev/null" else { return }; if let d=try? JSONEncoder().encode(entries){ try? d.write(to:file) } }
}

/// Trash selected candidates after revalidation. Returns per-item results. Dry-run when execute=false.
public enum TrashExecutor {
    public static func run(_ items:[Candidate], allowedRoots:[String], execute:Bool, history:HistoryStore?) -> [(Candidate,String)] {
        items.map{ c in
            if let err = SafetyValidator.validate(c, allowedRoots:allowedRoots) { history?.add(.init(date:Date(),action:"trash",path:c.path,result:"skipped: \(err)")); return (c,"Skipped: \(err)") }
            guard execute else { return (c,"Dry-run OK — would move to Trash") }
            do { try FileManager.default.trashItem(at:URL(fileURLWithPath:c.path), resultingItemURL:nil); history?.add(.init(date:Date(),action:"trash",path:c.path,result:"trashed")); return (c,"Moved to Trash") }
            catch { history?.add(.init(date:Date(),action:"trash",path:c.path,result:"failed: \(error.localizedDescription)")); return (c,"Failed: \(error.localizedDescription)") }
        }
    }
}
public func fmtBytes(_ b:Int64) -> String { ByteCountFormatter.string(fromByteCount:b, countStyle:.file) }
