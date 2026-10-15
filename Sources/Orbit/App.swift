import SwiftUI
import OrbitCore

@main struct OrbitApp: App {
    @ObservedObject var model = Model.shared
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).frame(minWidth: 900, minHeight: 560) }
        MenuBarExtra("Orbit", systemImage: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Orbit — Your Mac, in balance.").font(.headline)
                Text("CPU \(Int(model.metrics.cpu))% · Memory \(fmtBytes(model.metrics.memUsed)) / \(fmtBytes(model.metrics.memTotal))")
                Text("Disk free \(fmtBytes(model.metrics.diskFree))")
                Button("Open Orbit") { NSApp.activate(ignoringOtherApps: true); for w in NSApp.windows { w.makeKeyAndOrderFront(nil) } }
                Button("Quit") { NSApp.terminate(nil) }
            }.padding()
        }
        Settings { SettingsView().environmentObject(model) }
    }
}

final class Model: ObservableObject {
    static let shared = Model()
    @Published var metrics = SystemMetrics.sample()
    @Published var history = HistoryStore()
    @Published var pollSeconds = 2.0
    init() { Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in DispatchQueue.global().async { let m = SystemMetrics.sample(); DispatchQueue.main.async { self?.metrics = m } } } }
    var allowedRoots: [String] { CleanupScanner().categories().map(\.root) + [NSHomeDirectory()+"/Applications", "/Applications"] }
    func reloadHistory() { history = HistoryStore() }
}

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                NavigationLink(destination: DashboardView()) { Label("Dashboard", systemImage: "gauge") }
                NavigationLink(destination: CleanupView()) { Label("Cleanup", systemImage: "sparkles") }
                NavigationLink(destination: DiskView()) { Label("Disk Analyzer", systemImage: "externaldrive") }
                NavigationLink(destination: AppsView()) { Label("Applications", systemImage: "square.grid.2x2") }
                NavigationLink(destination: MaintenanceView()) { Label("Maintenance", systemImage: "wrench.and.screwdriver") }
                NavigationLink(destination: ProcessesView()) { Label("Processes", systemImage: "list.bullet.rectangle") }
                NavigationLink(destination: HistoryView()) { Label("History", systemImage: "clock.arrow.circlepath") }
            }.navigationTitle("Orbit")
        } detail: { DashboardView() }
    }
}

struct MetricTile: View { var title: String; var value: String; var sub: String = ""; var frac: Double? = nil
    var body: some View { VStack(alignment:.leading, spacing:4){ Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.title3).monospacedDigit(); if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) }; if let f=frac { ProgressView(value: min(max(f,0),1)) } }.frame(maxWidth:.infinity, alignment:.leading).padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10)) } }

struct DashboardView: View {
    @EnvironmentObject var model: Model
    var body: some View {
        ScrollView { VStack(alignment:.leading, spacing:16) {
            Text("Your Mac, in balance.").font(.largeTitle.bold())
            LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())], spacing:12) {
                MetricTile(title:"CPU", value:String(format:"%.1f%%", model.metrics.cpu), frac: model.metrics.cpu/100)
                MetricTile(title:"Memory", value:fmtBytes(model.metrics.memUsed), sub:"of \(fmtBytes(model.metrics.memTotal))", frac: model.metrics.memTotal>0 ? Double(model.metrics.memUsed)/Double(model.metrics.memTotal) : nil)
                MetricTile(title:"Disk", value:"\(fmtBytes(model.metrics.diskFree)) free", sub:"of \(fmtBytes(model.metrics.diskTotal))", frac: model.metrics.diskTotal>0 ? 1-Double(model.metrics.diskFree)/Double(model.metrics.diskTotal) : nil)
                MetricTile(title:"Battery", value: model.metrics.battery.map{"\($0)%"} ?? "Unavailable", sub: model.metrics.battery == nil ? "No battery / not readable" : "")
                MetricTile(title:"Uptime", value: "\(Int(model.metrics.uptime/3600))h \(Int(model.metrics.uptime.truncatingRemainder(dividingBy:3600)/60))m")
                MetricTile(title:"Processes", value:"\(model.metrics.processCount)")
                MetricTile(title:"Temperature / Fan / GPU", value:"Unavailable", sub:"No public API without a privileged helper — not simulated")
            }
            Text("Metrics refresh every 2s from native APIs (host_statistics, volume capacity, IOKit power sources). Unavailable metrics are shown as unavailable, never simulated.").font(.caption).foregroundStyle(.secondary)
        }.padding() }.navigationTitle("Dashboard")
    }
}

final class CleanupVM: ObservableObject {
    @Published var items: [Candidate] = []; @Published var selected = Set<String>()
    @Published var results: [(Candidate,String)] = []; @Published var confirm = false; @Published var busy = false
    func scan() { busy=true; DispatchQueue.global().async { let s=CleanupScanner().scan(); DispatchQueue.main.async { self.items=s; self.busy=false; self.selected=Set(s.filter{$0.safety == .safe}.map(\.id)) } } }
}
struct CleanupView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var vm = CleanupVM()
    var total: Int64 { vm.items.filter{vm.selected.contains($0.id)}.reduce(0){$0+$1.size} }
    var body: some View {
        VStack(alignment:.leading) {
            HStack { Button("Scan (read-only)", action: vm.scan); if vm.busy { ProgressView().controlSize(.small) }
                Spacer(); Text("\(vm.items.count) candidates · \(fmtBytes(vm.items.reduce(0){$0+$1.size}))").foregroundStyle(.secondary)
                Button("Move selected to Trash…") { vm.confirm=true }.disabled(vm.selected.isEmpty) }
            Text("Review-first: scanning deletes nothing. Safe items pre-selected; Review items not. Execution revalidates path + inode, rejects symlinks/protected paths, moves to Trash (recoverable).").font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(vm.items) { c in
                    HStack { Toggle("", isOn: Binding(get:{vm.selected.contains(c.id)}, set:{ if $0 {vm.selected.insert(c.id)} else {vm.selected.remove(c.id)} })).labelsHidden().disabled(c.safety == .protected_)
                        VStack(alignment:.leading){ Text((c.path as NSString).lastPathComponent); Text(c.path).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer(); Text(c.category).font(.caption); Text(c.safety.rawValue).font(.caption.bold()).foregroundStyle(c.safety == .safe ? .green : .orange); Text(fmtBytes(c.size)).monospacedDigit() }
                }
            }
            if !vm.results.isEmpty { List(vm.results, id:\.0.id) { r in Text("\(r.1): \(r.0.path)").font(.caption) }.frame(height:120) }
        }.padding().navigationTitle("Cleanup")
        .alert("Move \(vm.selected.count) items (\(fmtBytes(total))) to Trash?", isPresented: $vm.confirm) {
            Button("Cancel", role:.cancel) {}
            Button("Move to Trash", role:.destructive) { let sel=vm.items.filter{vm.selected.contains($0.id)}; vm.results=TrashExecutor.run(sel, allowedRoots:model.allowedRoots, execute:true, history:model.history); model.reloadHistory(); vm.scan() }
        } message: { Text("Items move to Trash and can be restored. Paths are revalidated immediately before the operation; changed or unsafe items are skipped and reported.") }
    }
}

final class DiskVM: ObservableObject {
    @Published var path = NSHomeDirectory(); @Published var entries:[DiskEntry]=[]; @Published var complete=true
    @Published var query=""; @Published var sortSize=true; @Published var trashTarget: DiskEntry? = nil
    func load(){ let p=path; DispatchQueue.global().async{ let r=DiskScanner.scan(p); DispatchQueue.main.async{ self.entries=r.entries; self.complete=r.complete } } }
}
struct DiskView: View {
    @ObservedObject var vm = DiskVM()
    var shown: [DiskEntry] { var e = vm.entries.filter{ vm.query.isEmpty || $0.name.localizedCaseInsensitiveContains(vm.query) }; e.sort{ vm.sortSize ? $0.size>$1.size : $0.name<$1.name }; return e }
    var body: some View {
        VStack(alignment:.leading) {
            HStack { Button { let p=(vm.path as NSString).deletingLastPathComponent; if p != vm.path { vm.path=p; vm.load() } } label:{ Image(systemName:"chevron.left") }
                Text(vm.path).font(.callout).lineLimit(1); Spacer()
                Picker("", selection:$vm.sortSize){ Text("Size").tag(true); Text("Name").tag(false) }.pickerStyle(.segmented).frame(width:140)
                TextField("Filter", text:$vm.query).frame(width:160) }
            if !vm.complete { Text("Partial scan — some directories unreadable; sizes are a lower bound.").font(.caption).foregroundStyle(.orange) }
            List(shown) { e in
                HStack { Image(systemName: e.isDir ? "folder" : "doc"); VStack(alignment:.leading){ Text(e.name); if !e.complete { Text("partial").font(.caption).foregroundStyle(.orange) } }
                    Spacer(); Text(fmtBytes(e.size)).monospacedDigit()
                    Button("Reveal") { NSWorkspace.shared.selectFile(e.path, inFileViewerRootedAtPath: (e.path as NSString).deletingLastPathComponent) }
                    if e.isDir { Button("Open") { vm.path=e.path; vm.load() } }
                    Button("Trash…") { vm.trashTarget=e } }
            }
        }.padding().navigationTitle("Disk Analyzer").onAppear(perform: vm.load)
        .alert("Move to Trash?", item:$vm.trashTarget) { e in
            Button("Cancel", role:.cancel) {}; Button("Move to Trash", role:.destructive) { try? FileManager.default.trashItem(at: URL(fileURLWithPath:e.path), resultingItemURL:nil); vm.load() }
        } message: { e in Text("\(e.path)\nSeparate confirmation for the disk analyzer. The item moves to Trash.") }
    }
}

final class AppsVM: ObservableObject { @Published var apps:[AppInfo]=[]; @Published var sel: AppInfo? = nil; @Published var leftovers:[String]=[]; @Published var confirm=false; @Published var msg=""
    func load(){ DispatchQueue.global().async{ let a=AppDiscovery.apps(); DispatchQueue.main.async{ self.apps=a } } } }
struct AppsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var vm = AppsVM()
    var body: some View {
        HStack(spacing:0) {
            List(vm.apps, selection:$vm.sel) { a in HStack{ VStack(alignment:.leading){ Text(a.name); Text(a.bundleID).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(fmtBytes(a.size)) }.tag(a) }
                .frame(width:380).onAppear(perform: vm.load)
            VStack(alignment:.leading, spacing:8) {
                if let a=vm.sel { Text(a.name).font(.title2.bold()); Text("Version \(a.version) · \(a.bundleID)"); Text(a.path).font(.caption).foregroundStyle(.secondary)
                    Text("Related files (verified by bundle ID):").font(.headline); ForEach(vm.leftovers,id:\.self){ Text($0).font(.caption) }
                    if vm.leftovers.isEmpty { Text("None found.").foregroundStyle(.secondary) }
                    Button("Uninstall… (move app + related files to Trash)") { vm.confirm=true }.disabled(a.path.hasPrefix("/System"))
                    Text(vm.msg).font(.caption)
                } else { Text("Select an application. Leftovers match only the exact bundle ID. Shared data and user documents are never included.").foregroundStyle(.secondary) }
                Spacer()
            }.padding()
        }.navigationTitle("Applications")
        .onChange(of: vm.sel) { a in vm.leftovers = a.map{ AppDiscovery.leftovers(bundleID:$0.bundleID) } ?? [] }
        .alert("Uninstall \(vm.sel?.name ?? "")?", isPresented:$vm.confirm) { Button("Cancel", role:.cancel){}; Button("Move to Trash", role:.destructive){
            guard let a=vm.sel else { return }; var done=0; var failed:[String]=[]
            for p in [a.path]+vm.leftovers { do { try FileManager.default.trashItem(at:URL(fileURLWithPath:p), resultingItemURL:nil); done+=1; model.history.add(.init(date:Date(),action:"uninstall",path:p,result:"trashed")) } catch { failed.append("\(p): \(error.localizedDescription)") } }
            model.reloadHistory(); vm.msg = "Trashed \(done). Failed: \(failed.joined(separator:"; "))"; vm.load(); vm.sel=nil
        } } message: { Text("Only the app bundle and the listed bundle-ID files move to Trash. Nothing else is touched.") }
    }
}

final class MaintVM: ObservableObject { @Published var log:[String]=[]
    func run(_ label:String, _ exe:String, _ args:[String]) { let p=Process(); p.executableURL=URL(fileURLWithPath:exe); p.arguments=args; let pipe=Pipe(); p.standardOutput=pipe; p.standardError=pipe
        do { try p.run(); p.waitUntilExit(); let out=String(data:pipe.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8) ?? ""; log.insert("\(label): exit \(p.terminationStatus) \(out.prefix(120))", at:0) } catch { log.insert("\(label): failed \(error.localizedDescription)", at:0) } } }
struct MaintenanceView: View { @ObservedObject var vm = MaintVM()
    var body: some View { VStack(alignment:.leading, spacing:10) {
        Text("User-level maintenance. No sudo, no system files modified. Failures are reported, not hidden.").font(.caption).foregroundStyle(.secondary)
        Button("Refresh Quick Look cache (qlmanage -r cache)") { vm.run("QuickLook","/usr/bin/qlmanage",["-r","cache"]) }
        Button("Flush DNS cache (dscacheutil -flushcache)") { vm.run("DNS","/usr/bin/dscacheutil",["-flushcache"]) }
        Button("Refresh icon services (killall iconservicesagent — restarts automatically)") { vm.run("Icons","/usr/bin/killall",["iconservicesagent"]) }
        List(vm.log,id:\.self){ Text($0).font(.caption.monospaced()) }; Spacer()
    }.padding().navigationTitle("Maintenance") } }

final class ProcVM: ObservableObject { @Published var procs:[ProcInfo]=[]; @Published var query=""; @Published var killTarget: ProcInfo? = nil
    func load(){ DispatchQueue.global().async{ let p=ProcessList.list(); DispatchQueue.main.async{ self.procs=p } } } }
struct ProcessesView: View { @ObservedObject var vm = ProcVM()
    var shown:[ProcInfo]{ vm.procs.filter{ vm.query.isEmpty || $0.name.localizedCaseInsensitiveContains(vm.query) }.sorted{$0.cpu>$1.cpu} }
    var body: some View { VStack { HStack{ TextField("Filter", text:$vm.query); Button("Refresh", action:vm.load) }
        List(shown){ p in HStack{ Text(p.name); Spacer(); Text("PID \(p.pid)").foregroundStyle(.secondary); Text(String(format:"%.1f%% CPU",p.cpu)); Text(fmtBytes(p.memKB*1024)); Text(p.user).foregroundStyle(.secondary)
            Button("Terminate…"){ vm.killTarget=p }.disabled(p.pid < 100 || p.user != NSUserName()) } }
        Text("You can terminate only your own non-system processes, after confirmation. SIGTERM is sent; apps may prompt to save.").font(.caption).foregroundStyle(.secondary)
    }.padding().navigationTitle("Processes").onAppear(perform:vm.load)
    .alert("Terminate process?", item:$vm.killTarget){ p in Button("Cancel", role:.cancel){}; Button("Terminate", role:.destructive){ _=ProcessList.terminate(pid:p.pid); vm.load() } } message:{ p in Text("\(p.name) (PID \(p.pid)) will receive SIGTERM. Unsaved work in that process may be lost.") } } }

struct HistoryView: View { @EnvironmentObject var model: Model
    var body: some View { List(model.history.entries){ e in VStack(alignment:.leading){ Text("\(e.action) — \(e.result)"); Text("\(e.date.formatted()) · \(e.path)").font(.caption).foregroundStyle(.secondary) } }.navigationTitle("History")
        .overlay { if model.history.entries.isEmpty { Text("No operations yet. History: ~/Library/Application Support/Orbit/history.json (max 500).") } } } }

struct SettingsView: View { @EnvironmentObject var model: Model
    var body: some View { Form {
        Text("Orbit — Your Mac, in balance.").font(.headline)
        Text("History: ~/Library/Application Support/Orbit/history.json. No telemetry, no network, scans are local and read-only. Temperature/fan/GPU: unavailable without a privileged helper (not installed). App updates: not claimed — no reliable source integrated.").font(.caption)
        Slider(value:$model.pollSeconds, in:1...10, step:1){ Text("Poll interval (stored; dashboard timer 2s in this build)") }
    }.padding().frame(width:460) } }
