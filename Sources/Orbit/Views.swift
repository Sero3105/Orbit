import SwiftUI
import OrbitCore

final class CleanupVM: ObservableObject {
    @Published var items: [Candidate] = []; @Published var selected = Set<String>()
    @Published var results: [(Candidate,String)] = []; @Published var confirm = false; @Published var busy = false
    @Published var cancelled = false; var cancelFlag = false
    @Published var groups: [CleanupGroup] = []
    func cancel() { cancelFlag = true }
    func scan() { if busy { return }; busy=true; cancelled=false; cancelFlag=false
        DispatchQueue.global().async { let s=CleanupScanner().scan(shouldCancel: { [weak self] in self?.cancelFlag ?? true })
            DispatchQueue.main.async { self.items=s; self.groups=Dictionary(grouping:s, by: \.category).sorted{ $0.key < $1.key }.map{ g in CleanupGroup(id: g.key, title: fmtBytes(g.value.reduce(0){$0+$1.size}), items: g.value.sorted{ $0.size > $1.size }) }; self.busy=false; self.cancelled=self.cancelFlag; self.selected=Set(s.filter{$0.safety == .safe}.map(\.id)) } } }
}
struct CleanupGroup: Identifiable { var id: String; var title: String; var items: [Candidate] }
struct CleanupRow: View {
    @ObservedObject var vm: CleanupVM; var c: Candidate
    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { vm.selected.contains(c.id) }, set: { on in if on { vm.selected.insert(c.id) } else { vm.selected.remove(c.id) } })).labelsHidden().disabled(c.safety == .protected_)
            VStack(alignment:.leading, spacing: 2){ Text((c.path as NSString).lastPathComponent).font(.system(size: 12.5, weight: .medium)).foregroundStyle(T.ink); Text(c.path).font(.system(size: 10.5)).foregroundStyle(T.muted).lineLimit(1) }
            Spacer(); Text(tr(c.category)).font(.system(size: 10.5)).foregroundStyle(T.muted)
            StatusChip(text: c.safety.rawValue, color: c.safety == .safe ? T.accent : T.amber)
            Text(fmtBytes(c.size)).font(.system(size: 12, weight: .medium)).monospacedDigit().foregroundStyle(T.ink).frame(width: 76, alignment: .trailing)
        }
    }
}
struct CleanupView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var vm: CleanupVM
    var total: Int64 { vm.items.filter{vm.selected.contains($0.id)}.reduce(0){$0+$1.size} }
    var body: some View {
        VStack(alignment:.leading, spacing: 14) {
            HStack(alignment:.top) { SectionTitle(title: model.t("Cleanup"), sub: model.t("Review-first. Scanning deletes nothing; execution revalidates every path before moving it to Trash."))
                Spacer(); StatusChip(text: "\(vm.items.count) \(tr("candidates")) · \(fmtBytes(vm.items.reduce(0){$0+$1.size}))", color: T.cyan) }
            if !model.accessGranted("cleanup") {
                PermissionGate(icon: "sparkles", title: model.t("Cleanup needs folder access"),
                    bodyText: "To find reclaimable space, Orbit reads the names and sizes of files in your Library Caches, Library Logs, Downloads and ~/.cache. It reads nothing else, uploads nothing, and deletes nothing without your review and confirmation.",
                    onEnable: { model.setAccess("cleanup", true) }, onSkip: { model.setAccess("cleanup", false) })
            }
            HStack(spacing: 10) {
                Button(model.t("Scan (read-only)"), action: vm.scan).buttonStyle(AccentButtonStyle()).disabled(vm.busy || !model.accessGranted("cleanup"))
                if vm.busy { ProgressView().controlSize(.small); Button(tr("Cancel"), action: vm.cancel).buttonStyle(GhostButtonStyle()) }
                if vm.cancelled { StatusChip(text: "Scan cancelled — partial results", color: T.amber) }
                Spacer()
                Button(model.t("Move selected to Trash…")) { vm.confirm=true }.buttonStyle(DangerButtonStyle()).disabled(vm.selected.isEmpty).opacity(vm.selected.isEmpty ? 0.45 : 1)
            }
            if vm.items.isEmpty && !vm.busy {
                Panel { EmptyState(icon: "sparkles", title: model.t("No scan yet"), sub: "Run a read-only scan to see reclaimable caches, logs, old installers and AI-tool caches. Safe items are pre-selected; review items never are.") }
            } else {
                List {
                    ForEach(vm.groups) { g in
                        Text("\(tr(g.id)) · \(g.title)").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                        ForEach(g.items) { c in CleanupRow(vm: vm, c: c) }
                    }
                }.scrollContentBackground(.hidden)
            }
            if !vm.results.isEmpty { Panel(pad: 10) { VStack(alignment:.leading, spacing: 3) { ForEach(vm.results, id:\.0.id) { r in Text("\(trStatus(r.1)): \(r.0.path)").font(.system(size: 10.5)).foregroundStyle(T.muted) } } }.frame(maxHeight: 110) }
            Spacer(minLength: 0)
        }.padding(22).background(T.bg).navigationTitle(model.t("Cleanup"))
        .alert(String(format: tr("Move %d items (%@) to Trash?"), vm.selected.count, fmtBytes(total)), isPresented: $vm.confirm) {
            Button(tr("Cancel"), role:.cancel) {}
            Button(tr("Move to Trash"), role:.destructive) { let sel=vm.items.filter{vm.selected.contains($0.id)}; vm.results=TrashExecutor.run(sel, allowedRoots:model.allowedRoots, execute:true, history:model.history); model.reloadHistory(); vm.scan() }
        } message: { Text(tr("Items move to Trash and can be restored. Paths are revalidated immediately before the operation; changed or unsafe items are skipped and reported.")) }
    }
}

final class DiskVM: ObservableObject {
    @Published var path = NSHomeDirectory(); @Published var entries:[DiskEntry]=[]; @Published var complete=true
    @Published var query=""; @Published var sortMode=0; @Published var trashTarget: DiskEntry? = nil
    var sortTitle: String { ["Size ↓ largest","Size ↑ smallest","Name A–Z","Name Z–A"][sortMode] }
    @Published var busy=false; var cancelFlag=false
    func cancel(){ cancelFlag=true }
    func load(){ if busy { return }; busy=true; cancelFlag=false; let p=path; DispatchQueue.global().async{ let r=DiskScanner.scan(p, shouldCancel:{ [weak self] in self?.cancelFlag ?? true }); DispatchQueue.main.async{ self.entries=r.entries; self.complete=r.complete; self.busy=false } } }
}
struct DiskView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var vm: DiskVM
    var shown: [DiskEntry] { var e = vm.entries.filter{ vm.query.isEmpty || $0.name.localizedCaseInsensitiveContains(vm.query) }
        switch vm.sortMode { case 1: e.sort{$0.size<$1.size}; case 2: e.sort{$0.name.lowercased()<$1.name.lowercased()}; case 3: e.sort{$0.name.lowercased()>$1.name.lowercased()}; default: e.sort{$0.size>$1.size} }; return e }
    var maxSize: Int64 { shown.map(\.size).max() ?? 1 }
    var body: some View {
        VStack(alignment:.leading, spacing: 12) {
            SectionTitle(title: model.t("Disk Analyzer"), sub: model.t("Measured sizes. Partial scans are flagged — never reported as complete."))
            if !model.accessGranted("disk") {
                PermissionGate(icon: "externaldrive", title: model.t("Disk Analyzer needs folder access"),
                    bodyText: "Orbit measures the size of folders you open, starting with your home folder. Some system folders stay unreadable without extra macOS permission — those are reported as partial, never guessed.",
                    onEnable: { model.setAccess("disk", true); vm.load() }, onSkip: { model.setAccess("disk", false) })
            }
            HStack(spacing: 10) { Button { let p=(vm.path as NSString).deletingLastPathComponent; if p != vm.path { vm.path=p; vm.load() } } label:{ Image(systemName:"chevron.left") }.buttonStyle(GhostButtonStyle())
                Text(vm.path).font(.system(size: 12)).foregroundStyle(T.ink).lineLimit(1); Spacer()

                HStack(spacing: 7) { Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(T.muted)
                    TextField(model.t("Filter by name"), text:$vm.query).textFieldStyle(.plain) }
                    .padding(.horizontal, 10).padding(.vertical, 7).background(T.raised, in: RoundedRectangle(cornerRadius: 7)).frame(width: 200)
                Text("\(shown.count) \(tr("items"))").font(.system(size: 11)).foregroundStyle(T.muted) }
            HStack { if !vm.complete { StatusChip(text: model.t("Partial scan — some directories unreadable; sizes are a lower bound"), color: T.amber) }; if vm.busy { ProgressView().controlSize(.small); Button(model.t("Cancel scan"), action: vm.cancel).buttonStyle(GhostButtonStyle()) } }
            if vm.entries.isEmpty { Panel { EmptyState(icon: "externaldrive", title: model.t("Scanning…"), sub: "Measuring directory sizes. Large folders can take a while.") } }
            if !vm.entries.isEmpty { TreemapStrip(entries: Array(shown.prefix(11)).map{($0.name,$0.size,$0.isDir)} + [(name:tr("Other"), size: shown.dropFirst(11).reduce(0){$0+$1.size}, isDir:true)]).frame(height: 86) }
            HStack(spacing: 9) {
                SortHead(title: "Name", active: vm.sortMode >= 2, asc: vm.sortMode == 2, align: .center) { vm.sortMode = vm.sortMode == 2 ? 3 : 2 }
                Text("").frame(width: 90)
                SortHead(title: "Size", active: vm.sortMode < 2, asc: vm.sortMode == 1) { vm.sortMode = vm.sortMode == 0 ? 1 : 0 }.frame(width: 86)
                Text("").frame(width: 172)
            }.padding(.horizontal, 6)
            List(shown) { e in
                HStack(spacing: 9) { Image(systemName: e.isDir ? "folder" : "doc").foregroundStyle(e.isDir ? T.cyan : T.muted)
                    VStack(alignment:.leading, spacing: 1){ Text(e.name).font(.system(size: 12.5)).foregroundStyle(T.ink); if !e.complete { Text(tr("partial")).font(.system(size: 10)).foregroundStyle(T.amber) } }
                    Spacer(); MeterBar(value: maxSize > 0 ? Double(e.size)/Double(maxSize) : 0, color: T.cyan).frame(width: 90)
                    Text(fmtBytes(e.size)).font(.system(size: 12)).monospacedDigit().foregroundStyle(T.ink).frame(width: 86, alignment: .center)
                    Button(model.t("Reveal")) { NSWorkspace.shared.selectFile(e.path, inFileViewerRootedAtPath: (e.path as NSString).deletingLastPathComponent) }.buttonStyle(AccentTextButtonStyle()).frame(width: 54)
                    if e.isDir { Button(model.t("Open")) { vm.path=e.path; vm.load() }.buttonStyle(AccentTextButtonStyle()).frame(width: 46) } else { Text("").frame(width: 46) }
                    Button(model.t("Trash…")) { vm.trashTarget=e }.buttonStyle(AccentTextButtonStyle()).frame(width: 62).padding(.trailing, 10) }
                .listRowBackground(T.surface)
            }.scrollContentBackground(.hidden)
        }.padding(22).background(T.bg).navigationTitle(model.t("Disk Analyzer")).onAppear { if model.accessGranted("disk") { vm.load() } }
        .alert(tr("Move to Trash?"), item:$vm.trashTarget) { e in
            Button(tr("Cancel"), role:.cancel) {}; Button(tr("Move to Trash"), role:.destructive) { try? FileManager.default.trashItem(at: URL(fileURLWithPath:e.path), resultingItemURL:nil); vm.load() }
        } message: { e in Text("\(e.path)\n\(tr("Separate confirmation for the disk analyzer. The item moves to Trash."))") }
    }
}

final class AppsVM: ObservableObject { @Published var apps:[AppInfo]=[]; @Published var sortMode=0
    var sortTitle: String { ["Name A–Z","Size ↓ largest","Size ↑ smallest","Name Z–A"][sortMode] }
    var sorted: [AppInfo] { switch sortMode { case 1: return apps.sorted{$0.size>$1.size}; case 2: return apps.sorted{$0.size<$1.size}; case 3: return apps.sorted{$0.name.lowercased()>$1.name.lowercased()}; default: return apps.sorted{$0.name.lowercased()<$1.name.lowercased()} } }
    @Published var sel: AppInfo? = nil; @Published var leftovers:[String]=[]; @Published var confirm=false; @Published var msg=""
    @Published var plan: Uninstaller.Plan? = nil; @Published var block = ""
    /// Ownership checks read signatures and other apps, so they run off the main thread.
    func select(_ a: AppInfo?) { plan=nil; leftovers=[]; block=""; guard let a else { return }
        DispatchQueue.global().async { let r = Result { try Uninstaller.plan(appPath: a.path) }
            DispatchQueue.main.async { guard self.sel == a else { return }
                switch r { case .success(let p): self.plan=p; self.leftovers=p.leftovers; case .failure(let e): self.block = "\(e)" } } } }
    func load(){ DispatchQueue.global().async{ let a=AppDiscovery.apps(); DispatchQueue.main.async{ self.apps=a } } }
    func sizeOf(_ path:String) -> Int64 { var d: ObjCBool=false; if FileManager.default.fileExists(atPath:path,isDirectory:&d), d.boolValue { return SafetyValidator.dirSize(URL(fileURLWithPath:path)).0 }; return ((try? FileManager.default.attributesOfItem(atPath:path))?[.size] as? NSNumber)?.int64Value ?? 0 }
    func detail(_ a: AppInfo) -> [(String,String)] {
        let b = Bundle(path: a.path); let info = b?.infoDictionary ?? [:]
        let attrs = try? FileManager.default.attributesOfItem(atPath: a.path)
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .none
        var rows: [(String,String)] = [("Version", a.version), ("Bundle ID", a.bundleID), ("Size on disk", fmtBytes(a.size)), ("Location", a.path)]
        if let exe = info["CFBundleExecutable"] as? String { rows.append(("Executable", exe)) }
        if let min = info["LSMinimumSystemVersion"] as? String { rows.append(("Minimum macOS", min)) }
        if let cat = info["LSApplicationCategoryType"] as? String { rows.append(("Category", cat.replacingOccurrences(of: "public.app-category.", with: "").replacingOccurrences(of: "-", with: " "))) }
        if let d = attrs?[.modificationDate] as? Date { rows.append(("Last modified", df.string(from: d))) }
        if let d = attrs?[.creationDate] as? Date { rows.append(("Installed (created)", df.string(from: d))) }
        return rows
    } }
struct AppsView: View {
    @EnvironmentObject var model: Model
    @ObservedObject var vm: AppsVM
    var body: some View {
        VStack(alignment:.leading, spacing: 12) {
            SectionTitle(title: model.t("Applications"), sub: model.t("Installed apps and files verified by exact bundle ID. Shared data and user documents are never included."))
            if !model.accessGranted("apps") {
                PermissionGate(icon: "square.grid.2x2", title: model.t("Applications needs folder access"),
                    bodyText: "Orbit lists the apps in /Applications and your home Applications folder, reads their version and size, and looks up files matching their exact bundle ID. Nothing is removed without a preview and your confirmation.",
                    onEnable: { model.setAccess("apps", true); vm.load() }, onSkip: { model.setAccess("apps", false) })
            }
            HStack(alignment: .top, spacing: 16) {
                Panel(pad: 10) {
                    VStack(spacing: 8) {
                        HStack(spacing: 9) {
                            SortHead(title: "Application", active: vm.sortMode == 0 || vm.sortMode == 3, asc: vm.sortMode == 0) { vm.sortMode = vm.sortMode == 0 ? 3 : 0 }
                            SortHead(title: "Size", active: vm.sortMode == 1 || vm.sortMode == 2, asc: vm.sortMode == 2) { vm.sortMode = vm.sortMode == 1 ? 2 : 1 }.frame(width: 90)
                        }.padding(.horizontal, 6)
                        List(vm.sorted, selection:$vm.sel) { a in
                            HStack(spacing: 9) { Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 26, height: 26)
                                VStack(alignment:.leading, spacing: 1){ Text(a.name).font(.system(size: 12.5)).foregroundStyle(T.ink); Text("\(a.bundleID) · v\(a.version)").font(.system(size: 10)).foregroundStyle(T.muted).lineLimit(1) }
                                Spacer(); Text(fmtBytes(a.size)).font(.system(size: 11)).monospacedDigit().foregroundStyle(T.muted) }.tag(a)
                        }.scrollContentBackground(.hidden)
                    }
                }.frame(width: 430)
                .overlay { if vm.apps.isEmpty { VStack(spacing: 8){ ProgressView(); Text(model.t("Loading applications…")).font(.system(size: 11)).foregroundStyle(T.muted) } } }
                Panel { detail }
            }
        }.padding(22).background(T.bg).navigationTitle(model.t("Applications"))
        .onAppear { if model.accessGranted("apps") && vm.apps.isEmpty { vm.load() } }
        .onChange(of: vm.sel) { a in vm.select(a) }
        .alert("\(tr("Uninstall")) \(vm.sel?.name ?? "")?", isPresented:$vm.confirm) { Button(tr("Cancel"), role:.cancel){}; Button(tr("Move to Trash"), role:.destructive){
            guard let p=vm.plan else { return }
            DispatchQueue.global().async { let results = Uninstaller.execute(p)
                DispatchQueue.main.async {
                    for (path, o) in results { let r: String; switch o { case .trashed: r = "trashed"; case .skipped(let w): r = "skipped: \(w)"; case .failed(let w): r = "failed: \(w)" }
                        model.history.add(.init(date:Date(), action:"uninstall", path:path, result:r)) }
                    let done = results.filter { $0.1 == .trashed }.count
                    let notDone = results.filter { $0.1 != .trashed }.map { "\(($0.0 as NSString).lastPathComponent): \(trResult($0.1))" }
                    model.reloadHistory(); vm.msg = "\(tr("Trashed")) \(done)" + (notDone.isEmpty ? "" : ". \(tr("Not moved")): \(notDone.joined(separator:"; "))"); vm.load(); vm.sel=nil } }
        } } message: { Text(tr("Only the app bundle and the listed bundle-ID files move to Trash. Nothing else is touched.")) }
    }
    @ViewBuilder var detail: some View {
        if let a=vm.sel {
            VStack(alignment:.leading, spacing: 12) {
                HStack(spacing: 12) { Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 48, height: 48)
                    VStack(alignment:.leading, spacing: 2){ Text(a.name).font(.system(size: 20, weight: .semibold)).foregroundStyle(T.ink)
                        Text("\(tr("Version")) \(a.version) · \(fmtBytes(a.size)) \(tr("on disk"))").font(.system(size: 11)).foregroundStyle(T.muted) } }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 10) {
                    ForEach(vm.detail(a), id: \.0) { row in
                        VStack(alignment:.leading, spacing: 2){ Text(tr(row.0)).font(.system(size: 9.5, weight: .semibold)).foregroundStyle(T.muted); Text(row.1).font(.system(size: 11.5)).foregroundStyle(T.ink).lineLimit(2) } }
                }
                Text("\(tr("Related files")) · \(fmtBytes(vm.leftovers.reduce(0){ $0 + vm.sizeOf($1) })) \(tr("total"))").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                if !vm.block.isEmpty { Text("\(tr("Orbit will not uninstall this app")): \(tr(vm.block))").font(.system(size: 11, weight: .medium)).foregroundStyle(T.amber) }
                else if vm.plan == nil { Text(tr("Checking which files belong to this app…")).font(.system(size: 11)).foregroundStyle(T.muted) }
                else if vm.plan?.sharedBundleID == true { Text(tr("Another installed copy uses the same bundle ID, so its data is shared: only this app bundle will be moved to Trash.")).font(.system(size: 11)).foregroundStyle(T.amber) }
                else if vm.leftovers.isEmpty { Text(tr("No preferences, caches or support files match this bundle ID.")).font(.system(size: 11)).foregroundStyle(T.muted) }
                ForEach(vm.leftovers,id:\.self){ lf in HStack { Text(lf).font(.system(size: 10.5)).foregroundStyle(T.ink).lineLimit(1); Spacer(); Text(fmtBytes(vm.sizeOf(lf))).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(T.muted) } }
                Text(tr("Update check: not available — no reliable source integrated, so Orbit does not claim updates.")).font(.system(size: 10.5)).foregroundStyle(T.muted)
                Spacer()
                HStack { Text(vm.msg).font(.system(size: 11)).foregroundStyle(T.muted); Spacer()
                    Button(tr("Uninstall… (app + listed files to Trash)")) { vm.confirm=true }.buttonStyle(DangerButtonStyle()).disabled(vm.plan == nil) }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(format: tr("%d applications · %@ total"), vm.apps.count, fmtBytes(vm.apps.reduce(0){$0+$1.size}))).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink)
                Text(tr("Largest applications — select one to see its details, related files and uninstall options.")).font(.system(size: 11)).foregroundStyle(T.muted)
                ForEach(vm.apps.sorted{$0.size>$1.size}.prefix(6), id: \.id) { a in
                    Button { vm.sel = a } label: { HStack(spacing: 9) { Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 24, height: 24)
                        Text(a.name).font(.system(size: 12.5)).foregroundStyle(T.ink); Spacer(); Text(fmtBytes(a.size)).font(.system(size: 11.5, weight: .medium)).monospacedDigit().foregroundStyle(T.ink) }.contentShape(Rectangle()) }.buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }
}

final class MaintVM: ObservableObject { @Published var log:[String]=[]; @Published var cacheInfo = ""
    func loadCacheInfo(){ DispatchQueue.global().async { let h=NSHomeDirectory(); let ql=SafetyValidator.dirSize(URL(fileURLWithPath: h+"/Library/Caches/com.apple.QuickLook.thumbnailcache")).0; let icons=SafetyValidator.dirSize(URL(fileURLWithPath: h+"/Library/Caches/com.apple.iconservices")).0; let all=SafetyValidator.dirSize(URL(fileURLWithPath: h+"/Library/Caches")).0
        DispatchQueue.main.async { self.cacheInfo = "\(tr("Right now: Quick Look cache")) \(fmtBytes(ql)) · \(tr("Icon cache")) \(fmtBytes(icons)) · \(tr("All user caches")) \(fmtBytes(all))" } } }
    func run(_ label:String, _ exe:String, _ args:[String]) { DispatchQueue.global().async { let p=Process(); p.executableURL=URL(fileURLWithPath:exe); p.arguments=args; let pipe=Pipe(); p.standardOutput=pipe; p.standardError=pipe
        do { try p.run(); let data=pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); let out=String(data:data,encoding:.utf8) ?? ""; DispatchQueue.main.async { self.log.insert("\(tr(label)): \(tr("exit code")) \(p.terminationStatus) \(out.prefix(120))", at:0) } } catch { DispatchQueue.main.async { self.log.insert("\(tr(label)): \(tr("failed")) \(error.localizedDescription)", at:0) } } } } }
struct MaintenanceView: View { @EnvironmentObject var model: Model
    @ObservedObject var vm: MaintVM
    var body: some View { VStack(alignment:.leading, spacing: 12) {
        SectionTitle(title: model.t("Maintenance"), sub: model.t("Fix a specific glitch. Find your symptom below, press its Run button, then read the result at the bottom."))
        Panel { VStack(alignment: .leading, spacing: 5) {
            Text(model.t("How to use this page")).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink)
            Text(tr("1. Match your symptom to a task.  2. Press Run — macOS rebuilds that cache itself.  3. The real outcome appears under Results. Nothing here speeds up your Mac, deletes your files, or needs an administrator password.")).font(.system(size: 11.5)).foregroundStyle(T.muted)
            if !vm.cacheInfo.isEmpty { Text(vm.cacheInfo).font(.system(size: 11)).foregroundStyle(T.cyan) }
        } }.onAppear(perform: vm.loadCacheInfo)
        task("Symptom: Finder previews or thumbnails are stale or broken", "Task: rebuild the Quick Look preview cache. Runs: qlmanage -r cache. First previews may be slower for a few minutes afterwards.", "eye") { vm.run("QuickLook","/usr/bin/qlmanage",["-r","cache"]) }
        task("Symptom: a website opens the wrong address after a network change", "Task: clear the DNS lookup cache. Runs: dscacheutil -flushcache. Lookups rebuild automatically; nothing else changes.", "network") { vm.run("DNS","/usr/bin/dscacheutil",["-flushcache"]) }
        task("Symptom: app icons in Finder or Launchpad are generic or wrong", "Task: restart the icon service. Runs: killall iconservicesagent — it relaunches itself and redraws icons.", "app.badge") { vm.run("Icons","/usr/bin/killall",["iconservicesagent"]) }
        VStack(alignment: .leading, spacing: 6) { Text(model.t("Results")).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink)
            if vm.log.isEmpty { Text(tr("Nothing run yet in this session. When you press Run, the task name, exit code and any output will be listed here.")).font(.system(size: 11.5)).foregroundStyle(T.muted) }
            ForEach(vm.log,id:\.self){ Text($0).font(.system(size: 11).monospaced()).foregroundStyle(T.muted) } }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(T.surface, in: RoundedRectangle(cornerRadius: T.radius))
        Spacer()
    }.padding(22).background(T.bg).navigationTitle(model.t("Maintenance")) }
    func task(_ title:String, _ sub:String, _ icon:String, _ action:@escaping ()->Void) -> some View {
        Panel { HStack(spacing: 12) { Image(systemName: icon).foregroundStyle(T.accent).frame(width: 20)
            VStack(alignment:.leading, spacing: 2){ Text(tr(title)).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink); Text(tr(sub)).font(.system(size: 11)).foregroundStyle(T.muted) }
            Spacer(); Button(model.t("Run"), action: action).buttonStyle(GhostButtonStyle()) } }
    }
}

final class ProcVM: ObservableObject { @Published var procs:[ProcInfo]=[]; @Published var query=""; @Published var killTarget: ProcInfo? = nil; @Published var sortKey="cpu"; @Published var sortAsc=false
    func sortBy(_ key:String){ if sortKey==key { sortAsc.toggle() } else { sortKey=key; sortAsc=(key=="name"||key=="pid"||key=="user") } }
    func load(){ DispatchQueue.global().async{ let p=ProcessList.list(); DispatchQueue.main.async{ self.procs=p } } } }
struct ProcessesView: View { @EnvironmentObject var model: Model
    @ObservedObject var vm: ProcVM
    func head(_ title: String, _ key: String, _ align: Alignment) -> some View {
        Button { vm.sortBy(key) } label: {
            HStack(spacing: 4) { Text(tr(title)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(vm.sortKey == key ? T.ink : T.muted)
                if vm.sortKey == key { Image(systemName: vm.sortAsc ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .bold)).foregroundStyle(T.accent) } }
            .frame(maxWidth: .infinity, alignment: .center).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var shown:[ProcInfo]{ let f = vm.procs.filter{ vm.query.isEmpty || $0.name.localizedCaseInsensitiveContains(vm.query) }
        let sorted: [ProcInfo]
        switch vm.sortKey { case "memory": sorted=f.sorted{$0.memKB<$1.memKB}; case "name": sorted=f.sorted{$0.name.lowercased()<$1.name.lowercased()}; case "pid": sorted=f.sorted{$0.pid<$1.pid}; case "user": sorted=f.sorted{$0.user.lowercased()<$1.user.lowercased()}; default: sorted=f.sorted{$0.cpu<$1.cpu} }
        return vm.sortAsc ? sorted : sorted.reversed() }
    var body: some View { VStack(alignment:.leading, spacing: 12) {
        HStack(alignment:.top){ SectionTitle(title: model.t("Processes"), sub: "Live process table — sort it how you like. Termination is explicit, confirmed, and limited to your own processes.")
            Spacer(); Button(model.t("Refresh"), action:vm.load).buttonStyle(GhostButtonStyle()) }
        HStack(spacing: 12) {
            HStack(spacing: 7) { Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(T.muted)
                TextField(model.t("Filter by name"), text:$vm.query).textFieldStyle(.plain) }
                .padding(.horizontal, 10).padding(.vertical, 7).background(T.raised, in: RoundedRectangle(cornerRadius: 7)).frame(maxWidth: 320)

            Text("\(shown.count) \(tr("processes"))").font(.system(size: 11)).foregroundStyle(T.muted)
            Spacer()
        }
        if vm.procs.isEmpty { Panel { EmptyState(icon: "list.bullet.rectangle", title: model.t("Loading processes…"), sub: "Reading the live process table.") } }
        HStack(spacing: 9) {
            head("Process", "name", .leading).frame(maxWidth: .infinity, alignment: .leading)
            head("PID", "pid", .trailing).frame(width: 64, alignment: .trailing)
            head("CPU", "cpu", .trailing).frame(width: 147, alignment: .trailing)
            head(model.t("Memory"), "memory", .trailing).frame(width: 84, alignment: .trailing)
            head("User", "user", .leading).frame(width: 132, alignment: .leading)
            Text("").frame(width: 96)
        }.padding(.horizontal, 6)
        List(shown){ p in HStack(spacing: 9){
            Text(p.name).font(.system(size: 12.5)).foregroundStyle(T.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text("\(p.pid)").font(.system(size: 11)).monospacedDigit().foregroundStyle(T.muted).frame(width: 64, alignment: .trailing)
            Text(String(format:"%.1f%%",p.cpu)).font(.system(size: 11.5, weight: p.cpu > 50 ? .semibold : .regular)).monospacedDigit().foregroundStyle(p.cpu > 50 ? T.amber : T.ink).frame(width: 78, alignment: .trailing)
            MeterBar(value: p.cpu/100, color: p.cpu > 50 ? T.amber : T.accent).frame(width: 60)
            Text(fmtBytes(p.memKB*1024)).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(T.ink).frame(width: 84, alignment: .trailing)
            Text(p.user).font(.system(size: 11)).foregroundStyle(T.muted).lineLimit(1).frame(width: 132, alignment: .leading)
            Button(model.t("Terminate…")){ vm.killTarget=p }.buttonStyle(GhostButtonStyle()).disabled(p.pid < 100 || p.user != NSUserName()).frame(width: 96)
        }.listRowBackground(T.surface) }
            .scrollContentBackground(.hidden)
    }.padding(22).background(T.bg).navigationTitle(model.t("Processes")).onAppear(perform:vm.load)
    .alert(tr("Terminate process?"), item:$vm.killTarget){ p in Button(tr("Cancel"), role:.cancel){}; Button(tr("Terminate"), role:.destructive){ _=ProcessList.terminate(pid:p.pid); vm.load() } } message:{ p in Text("\(p.name) (PID \(p.pid)) \(tr("will receive SIGTERM. Unsaved work in that process may be lost."))") } } }

struct HistoryView: View { @EnvironmentObject var model: Model
    var body: some View { VStack(alignment:.leading, spacing: 12) {
        HStack(alignment:.top){ SectionTitle(title: model.t("History"), sub: model.t("Everything Orbit has changed on this Mac, recorded locally. Nothing is uploaded, ever."))
            Spacer(); StatusChip(text: "\(model.history.entries.count) \(tr("operations"))", color: T.cyan) }
        Panel { VStack(alignment:.leading, spacing: 6) {
            Text(model.t("What gets recorded")).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink)
            Text(tr("Every confirmed Cleanup move-to-Trash and every application uninstall, with date, path and outcome (trashed, skipped or failed, and why). Scans and browsing are not recorded. Stored in ~/Library/Application Support/Orbit/history.json (last 500 entries).")).font(.system(size: 11.5)).foregroundStyle(T.muted)
        } }
        if model.history.entries.isEmpty { Panel(pad: 12) { HStack(spacing: 10){ Image(systemName: "clock.arrow.circlepath").foregroundStyle(T.muted); Text(tr("No operations yet — run a Cleanup scan and confirm an action, and it will be listed here.")).font(.system(size: 12)).foregroundStyle(T.muted) } } }
        else { List(model.history.entries){ e in VStack(alignment:.leading, spacing: 2){ HStack{ Text(tr(e.action)).font(.system(size: 12.5, weight: .medium)).foregroundStyle(T.ink); Text(trStatus(e.result)).font(.system(size: 11)).foregroundStyle(e.result.hasPrefix("trashed") ? T.accent : T.muted); Spacer(); Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(T.muted) }
            Text(e.path).font(.system(size: 10.5)).foregroundStyle(T.muted).lineLimit(1) }.listRowBackground(T.surface) }.scrollContentBackground(.hidden) }
    }.padding(22).background(T.bg).navigationTitle(model.t("History")) } }

struct SettingsView: View { @EnvironmentObject var model: Model
    var body: some View { Form {
        Text(tr("Orbit — Your Mac, in balance.")).font(.headline)
        Picker(tr("Language / Lingua"), selection: Binding(get: { model.lang }, set: { model.setLang($0) })) { Text(tr("English")).tag("en"); Text(tr("Italiano")).tag("it") }
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("Saved folder-access choices")).font(.headline)
            Text([("cleanup", "Cleanup"), ("disk", "Disk Analyzer"), ("apps", "Applications")].map { "\(tr($0.1)): \(tr(model.accessGranted($0.0) ? "enabled" : "not enabled"))" }.joined(separator: " · ")).font(.caption)
            Button(tr("Reset saved access choices")) { model.resetAccess() }
            Text(tr("Resetting makes Orbit ask again the next time you open those sections. This controls Orbit's own prompt only; macOS privacy grants live in System Settings → Privacy & Security → Files & Folders / Full Disk Access.")).font(.caption)
        }
        Text(tr("History: ~/Library/Application Support/Orbit/history.json. No telemetry, no network, scans are local and read-only. Temperature/fan/GPU: unavailable without a privileged helper (not installed). App updates: not claimed — no reliable source integrated.")).font(.caption)
    }.padding().frame(width:460).preferredColorScheme(.dark) } }
