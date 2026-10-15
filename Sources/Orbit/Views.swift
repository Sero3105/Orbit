import SwiftUI
import OrbitCore

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
        VStack(alignment:.leading, spacing: 14) {
            HStack(alignment:.top) { SectionTitle(title: "Cleanup", sub: "Review-first. Scanning deletes nothing; execution revalidates every path before moving it to Trash.")
                Spacer(); StatusChip(text: "\(vm.items.count) candidates · \(fmtBytes(vm.items.reduce(0){$0+$1.size}))", color: T.cyan) }
            HStack(spacing: 10) {
                Button("Scan (read-only)", action: vm.scan).buttonStyle(AccentButtonStyle())
                if vm.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Move selected to Trash…") { vm.confirm=true }.buttonStyle(DangerButtonStyle()).disabled(vm.selected.isEmpty).opacity(vm.selected.isEmpty ? 0.45 : 1)
            }
            if vm.items.isEmpty && !vm.busy {
                Panel { EmptyState(icon: "sparkles", title: "No scan yet", sub: "Run a read-only scan to see reclaimable caches, logs, old installers and AI-tool caches. Safe items are pre-selected; review items never are.") }
            } else {
                List {
                    ForEach(vm.items) { c in
                        HStack(spacing: 10) { Toggle("", isOn: Binding(get:{vm.selected.contains(c.id)}, set:{ if $0 {vm.selected.insert(c.id)} else {vm.selected.remove(c.id)} })).labelsHidden().disabled(c.safety == .protected_)
                            VStack(alignment:.leading, spacing: 2){ Text((c.path as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium)).foregroundStyle(T.ink); Text(c.path).font(.system(size: 10.5)).foregroundStyle(T.muted).lineLimit(1) }
                            Spacer(); Text(c.category).font(.system(size: 10.5)).foregroundStyle(T.muted)
                            StatusChip(text: c.safety.rawValue, color: c.safety == .safe ? T.accent : T.amber)
                            Text(fmtBytes(c.size)).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(T.ink).frame(width: 76, alignment: .trailing) }
                        .listRowBackground(T.surface)
                    }
                }.scrollContentBackground(.hidden)
            }
            if !vm.results.isEmpty { Panel(pad: 10) { VStack(alignment:.leading, spacing: 3) { ForEach(vm.results, id:\.0.id) { r in Text("\(r.1): \(r.0.path)").font(.system(size: 10.5)).foregroundStyle(T.muted) } } }.frame(maxHeight: 110) }
            Spacer(minLength: 0)
        }.padding(22).background(T.bg).navigationTitle("Cleanup")
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
        VStack(alignment:.leading, spacing: 12) {
            SectionTitle(title: "Disk Analyzer", sub: "Measured sizes. Partial scans are flagged — never reported as complete.")
            HStack(spacing: 8) { Button { let p=(vm.path as NSString).deletingLastPathComponent; if p != vm.path { vm.path=p; vm.load() } } label:{ Image(systemName:"chevron.left") }.buttonStyle(GhostButtonStyle())
                Text(vm.path).font(.system(size: 12)).foregroundStyle(T.ink).lineLimit(1); Spacer()
                Picker("", selection:$vm.sortSize){ Text("Size").tag(true); Text("Name").tag(false) }.pickerStyle(.segmented).frame(width:140)
                TextField("Filter", text:$vm.query).frame(width:160) }
            if !vm.complete { StatusChip(text: "Partial scan — some directories unreadable; sizes are a lower bound", color: T.amber) }
            if vm.entries.isEmpty { Panel { EmptyState(icon: "externaldrive", title: "Scanning…", sub: "Measuring directory sizes. Large folders can take a while.") } }
            TreemapStrip(entries: Array(shown.prefix(11)).map{($0.name,$0.size,$0.isDir)} + [(name:"Other", size: shown.dropFirst(11).reduce(0){$0+$1.size}, isDir:true)]).frame(height: 86)
            List(shown) { e in
                HStack(spacing: 9) { Image(systemName: e.isDir ? "folder" : "doc").foregroundStyle(e.isDir ? T.cyan : T.muted)
                    VStack(alignment:.leading, spacing: 1){ Text(e.name).font(.system(size: 12.5)).foregroundStyle(T.ink); if !e.complete { Text("partial").font(.system(size: 10)).foregroundStyle(T.amber) } }
                    Spacer(); MeterBar(value: (shown.map(\.size).max() ?? 1) > 0 ? Double(e.size)/Double(shown.map(\.size).max() ?? 1) : 0, color: T.cyan).frame(width: 90)
                    Text(fmtBytes(e.size)).font(.system(size: 12)).monospacedDigit().foregroundStyle(T.ink).frame(width: 76, alignment: .trailing)
                    Button("Reveal") { NSWorkspace.shared.selectFile(e.path, inFileViewerRootedAtPath: (e.path as NSString).deletingLastPathComponent) }.buttonStyle(GhostButtonStyle())
                    if e.isDir { Button("Open") { vm.path=e.path; vm.load() }.buttonStyle(GhostButtonStyle()) }
                    Button("Trash…") { vm.trashTarget=e }.buttonStyle(GhostButtonStyle()) }
                .listRowBackground(T.surface)
            }.scrollContentBackground(.hidden)
        }.padding(22).background(T.bg).navigationTitle("Disk Analyzer").onAppear(perform: vm.load)
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
        VStack(alignment:.leading, spacing: 12) {
            SectionTitle(title: "Applications", sub: "Installed apps and files verified by exact bundle ID. Shared data and user documents are never included.")
            HStack(spacing:0) {
                List(vm.apps, selection:$vm.sel) { a in
                    HStack(spacing: 9) { Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 26, height: 26)
                        VStack(alignment:.leading, spacing: 1){ Text(a.name).font(.system(size: 12.5)).foregroundStyle(T.ink); Text("\(a.bundleID) · v\(a.version)").font(.system(size: 10)).foregroundStyle(T.muted).lineLimit(1) }
                        Spacer(); Text(fmtBytes(a.size)).font(.system(size: 11)).monospacedDigit().foregroundStyle(T.muted) }.tag(a).listRowBackground(T.surface)
                }.scrollContentBackground(.hidden).frame(width:400).onAppear(perform: vm.load)
                .overlay { if vm.apps.isEmpty { VStack(spacing: 8){ ProgressView(); Text("Loading applications…").font(.system(size: 11)).foregroundStyle(T.muted) } } }
                Panel { VStack(alignment:.leading, spacing: 8) {
                    if let a=vm.sel { Text(a.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(T.ink); Text("Version \(a.version) · \(a.bundleID)").font(.system(size: 11)).foregroundStyle(T.muted); Text(a.path).font(.system(size: 10.5)).foregroundStyle(T.muted)
                        Text("Related files").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted); ForEach(vm.leftovers,id:\.self){ Text($0).font(.system(size: 10.5)).foregroundStyle(T.ink) }
                        if vm.leftovers.isEmpty { Text("None found.").font(.system(size: 11)).foregroundStyle(T.muted) }
                        Text("Update check: not available — no reliable source integrated, so Orbit does not claim updates.").font(.system(size: 10.5)).foregroundStyle(T.muted)
                        Button("Uninstall… (app + listed files to Trash)") { vm.confirm=true }.buttonStyle(DangerButtonStyle()).disabled(a.path.hasPrefix("/System"))
                        Text(vm.msg).font(.system(size: 11)).foregroundStyle(T.muted)
                    } else { EmptyState(icon: "square.grid.2x2", title: "Select an application", sub: "Icons, version, bundle ID and measured size are shown here with any verified leftovers.") }
                    Spacer()
                } }
            }
        }.padding(22).background(T.bg).navigationTitle("Applications")
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
        do { try p.run(); let data=pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); let out=String(data:data,encoding:.utf8) ?? ""; log.insert("\(label): exit \(p.terminationStatus) \(out.prefix(120))", at:0) } catch { log.insert("\(label): failed \(error.localizedDescription)", at:0) } } }
struct MaintenanceView: View { @ObservedObject var vm = MaintVM()
    var body: some View { VStack(alignment:.leading, spacing: 12) {
        SectionTitle(title: "Maintenance", sub: "User-level tasks only. No sudo, no system files modified; every result is reported, including failures.")
        task("Quick Look cache", "Regenerates thumbnail and preview caches (qlmanage).", "eye") { vm.run("QuickLook","/usr/bin/qlmanage",["-r","cache"]) }
        task("DNS cache", "Flushes the local DNS resolver cache (dscacheutil).", "network") { vm.run("DNS","/usr/bin/dscacheutil",["-flushcache"]) }
        task("Icon services", "Restarts the icon agent so Finder redraws app icons; it relaunches automatically.", "app.badge") { vm.run("Icons","/usr/bin/killall",["iconservicesagent"]) }
        if vm.log.isEmpty { Panel { EmptyState(icon: "wrench.and.screwdriver", title: "No tasks run yet", sub: "Results will appear here with their real exit status.") } }
        else { Panel(pad: 10) { VStack(alignment:.leading, spacing: 4) { ForEach(vm.log,id:\.self){ Text($0).font(.system(size: 11).monospaced()).foregroundStyle(T.muted) } } } }
        Spacer()
    }.padding(22).background(T.bg).navigationTitle("Maintenance") }
    func task(_ title:String, _ sub:String, _ icon:String, _ action:@escaping ()->Void) -> some View {
        Panel { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(T.accent).frame(width: 20)
            VStack(alignment:.leading, spacing: 2){ Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink); Text(sub).font(.system(size: 11)).foregroundStyle(T.muted) }
            Spacer(); Button("Run", action: action).buttonStyle(GhostButtonStyle()) } }
    }
}

final class ProcVM: ObservableObject { @Published var procs:[ProcInfo]=[]; @Published var query=""; @Published var killTarget: ProcInfo? = nil
    func load(){ DispatchQueue.global().async{ let p=ProcessList.list(); DispatchQueue.main.async{ self.procs=p } } } }
struct ProcessesView: View { @ObservedObject var vm = ProcVM()
    var shown:[ProcInfo]{ vm.procs.filter{ vm.query.isEmpty || $0.name.localizedCaseInsensitiveContains(vm.query) }.sorted{$0.cpu>$1.cpu} }
    var body: some View { VStack(alignment:.leading, spacing: 12) {
        HStack(alignment:.top){ SectionTitle(title: "Processes", sub: "Live processes sorted by CPU. Termination is explicit, confirmed, and limited to your own processes.")
            Spacer(); Button("Refresh", action:vm.load).buttonStyle(GhostButtonStyle()) }
        TextField("Filter by name", text:$vm.query).frame(maxWidth: 320)
        if vm.procs.isEmpty { Panel { EmptyState(icon: "list.bullet.rectangle", title: "Loading processes…", sub: "Reading the live process table.") } }
        List(shown){ p in HStack(spacing: 9){ Text(p.name).font(.system(size: 12.5)).foregroundStyle(T.ink).lineLimit(1); Spacer()
            Text("PID \(p.pid)").font(.system(size: 11)).foregroundStyle(T.muted); Text(String(format:"%.1f%% CPU",p.cpu)).font(.system(size: 11.5, weight: p.cpu > 50 ? .semibold : .regular)).monospacedDigit().foregroundStyle(p.cpu > 50 ? T.amber : T.ink)
            MeterBar(value: p.cpu/100, color: p.cpu > 50 ? T.amber : T.accent).frame(width: 60)
            Text(fmtBytes(p.memKB*1024)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(T.ink).frame(width: 70, alignment: .trailing); Text(p.user).font(.system(size: 11)).foregroundStyle(T.muted)
            Button("Terminate…"){ vm.killTarget=p }.buttonStyle(GhostButtonStyle()).disabled(p.pid < 100 || p.user != NSUserName()) }.listRowBackground(T.surface) }
            .scrollContentBackground(.hidden)
    }.padding(22).background(T.bg).navigationTitle("Processes").onAppear(perform:vm.load)
    .alert("Terminate process?", item:$vm.killTarget){ p in Button("Cancel", role:.cancel){}; Button("Terminate", role:.destructive){ _=ProcessList.terminate(pid:p.pid); vm.load() } } message:{ p in Text("\(p.name) (PID \(p.pid)) will receive SIGTERM. Unsaved work in that process may be lost.") } } }

struct HistoryView: View { @EnvironmentObject var model: Model
    var body: some View { VStack(alignment:.leading, spacing: 12) {
        SectionTitle(title: "History", sub: "Local record only — stored in ~/Library/Application Support/Orbit/history.json, never uploaded.")
        if model.history.entries.isEmpty { Panel { EmptyState(icon: "clock.arrow.circlepath", title: "No operations yet", sub: "Confirmed cleanup and uninstall actions will appear here with their outcome.") } }
        else { List(model.history.entries){ e in VStack(alignment:.leading, spacing: 2){ HStack{ Text(e.action).font(.system(size: 12.5, weight: .medium)).foregroundStyle(T.ink); Text(e.result).font(.system(size: 11)).foregroundStyle(e.result.hasPrefix("trashed") ? T.accent : T.muted); Spacer(); Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(T.muted) }
            Text(e.path).font(.system(size: 10.5)).foregroundStyle(T.muted).lineLimit(1) }.listRowBackground(T.surface) }.scrollContentBackground(.hidden) }
    }.padding(22).background(T.bg).navigationTitle("History") } }

struct SettingsView: View { @EnvironmentObject var model: Model
    var body: some View { Form {
        Text("Orbit — Your Mac, in balance.").font(.headline)
        Text("History: ~/Library/Application Support/Orbit/history.json. No telemetry, no network, scans are local and read-only. Temperature/fan/GPU: unavailable without a privileged helper (not installed). App updates: not claimed — no reliable source integrated.").font(.caption)
    }.padding().frame(width:460).preferredColorScheme(.dark) } }
