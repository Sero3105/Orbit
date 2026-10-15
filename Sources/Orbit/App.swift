import SwiftUI
import OrbitCore

enum Section: String, CaseIterable { case dashboard = "Dashboard", energy = "Energy", cleanup = "Cleanup", disk = "Disk Analyzer", apps = "Applications", maintenance = "Maintenance", processes = "Processes", history = "History"
    var icon: String { switch self { case .dashboard: return "gauge.with.dots.needle.33percent"; case .energy: return "bolt"; case .cleanup: return "sparkles"; case .disk: return "externaldrive"; case .apps: return "square.grid.2x2"; case .maintenance: return "wrench.and.screwdriver"; case .processes: return "list.bullet.rectangle"; case .history: return "clock.arrow.circlepath" } } }

@main struct OrbitApp: App {
    @ObservedObject var model = Model.shared
    init() { let m = Model.shared; DispatchQueue.main.async { Snapshots.runIfRequested(model: m) } }
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).preferredColorScheme(.dark).frame(minWidth: 920, minHeight: 580) }
        MenuBarExtra("Orbit", systemImage: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Orbit — Your Mac, in balance.")).font(.headline)
                Text("CPU \(Int(model.metrics.cpu))% · \(tr("Memory")) \(fmtBytes(model.metrics.memUsed)) / \(fmtBytes(model.metrics.memTotal))")
                Text("\(tr("Disk free")) \(fmtBytes(model.metrics.diskFree))")
                if let p = model.power { Text(String(format: "%@ %.1f W", tr("Power"), p.wallW > 0 ? p.wallW : p.systemW)) }
                Button(tr("Open Orbit")) { NSApp.activate(ignoringOtherApps: true); for w in NSApp.windows { w.makeKeyAndOrderFront(nil) } }
                Button(tr("Quit")) { NSApp.terminate(nil) }
            }.padding()
        }
        Settings { SettingsView().environmentObject(model) }
    }
}

final class Model: ObservableObject {
    static let shared = Model()
    @Published var metrics = SystemMetrics.sample()
    @Published var history = HistoryStore()
    @Published var section: Section = .dashboard
    @Published var lang: String = UserDefaults.standard.string(forKey: "orbit.lang") ?? ((Locale.current.language.languageCode?.identifier ?? "en") == "it" ? "it" : "en")
    func setLang(_ l: String) { lang = l; UserDefaults.standard.set(l, forKey: "orbit.lang") }
    func t(_ en: String) -> String { lang == "it" ? (L10n.it[en] ?? en) : en }
    let cleanupVM = CleanupVM(); let diskVM = DiskVM(); let appsVM = AppsVM(); let procVM = ProcVM(); let maintVM = MaintVM()
    @Published var cpuSamples: [Double] = []
    @Published var memSamples: [Double] = []
    @Published var power: PowerReading? = PowerTelemetry.read()
    @Published var wattSamples: [Double] = []
    @Published var energy = EnergyLedger.load()
    @Published var kwhPrice: Double = UserDefaults.standard.double(forKey: "orbit.kwhPrice") { didSet { UserDefaults.standard.set(kwhPrice, forKey: "orbit.kwhPrice") } }
    private var lastPowerTick = Date()
    private var ticks = 0
    /// Integrate wall power into the per-day ledger; gaps over 10s (sleep, app suspended) are not counted.
    func recordPower(_ p: PowerReading?) {
        power = p
        let now = Date(), dt = now.timeIntervalSince(lastPowerTick); lastPowerTick = now
        guard let p else { return }
        wattSamples.append(p.wallW > 0 ? p.wallW : p.systemW); if wattSamples.count > 45 { wattSamples.removeFirst() }
        if dt <= 10 { energy.add(watts: p.wallW, seconds: dt, at: now) }
        ticks += 1; if ticks % 15 == 0 { energy.save() }
    }
    init() { NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.energy.save() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in DispatchQueue.global().async { let m = SystemMetrics.sample(); let p = PowerTelemetry.read(); DispatchQueue.main.async { guard let self else { return }; self.metrics = m; self.recordPower(p); self.cpuSamples.append(m.cpu); self.memSamples.append(m.memTotal > 0 ? Double(m.memUsed)/Double(m.memTotal)*100 : 0); if self.cpuSamples.count > 45 { self.cpuSamples.removeFirst() ; self.memSamples.removeFirst() } } } } }
    var allowedRoots: [String] { CleanupScanner().categories().map(\.root) + [NSHomeDirectory()+"/Applications", "/Applications"] }
    func accessGranted(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: "orbit.access.\(key)") }
    func setAccess(_ key: String, _ v: Bool) { UserDefaults.standard.set(v, forKey: "orbit.access.\(key)"); objectWillChange.send() }
    func resetAccess() { for k in ["cleanup","disk","apps"] { UserDefaults.standard.removeObject(forKey: "orbit.access.\(k)") }; objectWillChange.send() }
    func reloadHistory() { history = HistoryStore() }
}

struct ContentView: View {
    @EnvironmentObject var model: Model
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 212)
            Rectangle().fill(T.surface).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }.background(T.bg)
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                ZStack { Circle().stroke(T.accent, lineWidth: 2.5).frame(width: 22, height: 22)
                    Circle().fill(T.accent).frame(width: 5, height: 5).offset(x: 8, y: -8) }
                VStack(alignment: .leading, spacing: 0) { Text(tr("Orbit")).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink)
                    Text(model.t("Your Mac, in balance.")).font(.system(size: 9)).foregroundStyle(T.muted) }
            }.padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 18)
            Text(model.t("Monitor")).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted).padding(.horizontal, 16).padding(.bottom, 4)
            navItem(.dashboard); navItem(.energy); navItem(.processes)
            Text(model.t("Manage")).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            navItem(.cleanup); navItem(.disk); navItem(.apps); navItem(.maintenance)
            Text(model.t("Record")).font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            navItem(.history)
            Spacer()
            StatusChip(text: model.t(healthStatus(model.metrics).0), color: healthStatus(model.metrics).1).padding(.horizontal, 14).padding(.top, 14)
            HStack(spacing: 6) {
                langBtn("EN", "en"); langBtn("IT", "it"); Spacer()
            }.padding(.horizontal, 14).padding(.bottom, 14)
        }.background(T.bg)
    }
    func langBtn(_ label: String, _ code: String) -> some View {
        Button(label) { model.setLang(code) }
            .font(.system(size: 10.5, weight: model.lang == code ? .semibold : .regular))
            .foregroundStyle(model.lang == code ? .black : T.muted)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(model.lang == code ? T.accent : T.raised, in: Capsule()).buttonStyle(.plain)
    }
    func navItem(_ s: Section) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { model.section = s } } label: {
            HStack(spacing: 9) {
                Image(systemName: s.icon).font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(model.section == s ? T.accent : T.muted)
                Text(model.t(s.rawValue)).font(.system(size: 12.5, weight: model.section == s ? .semibold : .regular))
                    .foregroundStyle(model.section == s ? T.ink : T.muted)
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
            .background(model.section == s ? T.raised : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }
    @ViewBuilder var detail: some View {
        switch model.section {
        case .dashboard: DashboardView()
        case .energy: EnergyView()
        case .cleanup: CleanupView(vm: model.cleanupVM)
        case .disk: DiskView(vm: model.diskVM)
        case .apps: AppsView(vm: model.appsVM)
        case .maintenance: MaintenanceView(vm: model.maintVM)
        case .processes: ProcessesView(vm: model.procVM)
        case .history: HistoryView()
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var model: Model
    var m: Metrics { model.metrics }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle(title: model.t("Dashboard"), sub: model.t("Live system state from native macOS APIs. Nothing here is simulated."))
                Spacer()
                StatusChip(text: model.t("Live · updating every 2s"), color: T.accent)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    processorPanel
                    topCpuPanel
                }
                VStack(spacing: 16) {
                    storagePanel
                    HStack(spacing: 16) { uptimePanel; processesPanel }
                    memoryPanel
                    batteryPanel
                }.frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(model.t("Quick actions")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                HStack(spacing: 10) {
                    quick(model.t("Scan for cleanup"), "sparkles", .cleanup); quick(model.t("Analyze disk"), "externaldrive", .disk)
                    quick(model.t("Review applications"), "square.grid.2x2", .apps); quick(model.t("Inspect processes"), "list.bullet.rectangle", .processes); quick(model.t("Maintenance"), "wrench.and.screwdriver", .maintenance)
                }
            }
            recentPanel
        }.padding(22) }.background(T.bg)
        .onAppear { if model.procVM.procs.isEmpty { model.procVM.load() } }
    }
    var processorPanel: some View { Panel { VStack(alignment: .leading, spacing: 12) {
        Text(model.t("Processor")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        HStack(spacing: 20) {
            RingGauge(value: m.cpu/100, label: "CPU", big: String(format: "%.0f%%", m.cpu)).frame(width: 124, height: 124)
            VStack(alignment: .leading, spacing: 6) {
                Text(model.t("Memory")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                Text(fmtBytes(m.memUsed)).font(.system(size: 24, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
                Text(String(format: tr("of %@ used"), fmtBytes(m.memTotal))).font(.system(size: 11)).foregroundStyle(T.muted)
                MeterBar(value: m.memTotal > 0 ? Double(m.memUsed)/Double(m.memTotal) : 0, color: T.cyan).frame(width: 180)
            }
        }
        Text(tr("Session trend — real samples since launch, 2s interval")).font(.system(size: 10)).foregroundStyle(T.muted)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) { Text(tr("CPU")).font(.system(size: 9)).foregroundStyle(T.muted); Sparkline(samples: model.cpuSamples).frame(width: 200, height: 36) }
            VStack(alignment: .leading, spacing: 3) { Text(tr("Memory %")).font(.system(size: 9)).foregroundStyle(T.muted); Sparkline(samples: model.memSamples, color: T.cyan).frame(width: 200, height: 36) }
        }
        HStack(spacing: 26) {
            stat("Peak CPU (session)", model.cpuSamples.max().map{ String(format:"%.0f%%", $0) } ?? "—")
            stat("Peak memory (session)", model.memSamples.max().map{ String(format:"%.0f%%", $0) } ?? "—")
            stat("Samples", "\(model.cpuSamples.count)")
        }
    } } }
    var topCpuPanel: some View { Panel { VStack(alignment: .leading, spacing: 8) {
        HStack { Text(model.t("Top processes · CPU")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted); Spacer(); Button(model.t("Open Processes")) { model.section = .processes }.buttonStyle(GhostButtonStyle()) }
        if model.procVM.procs.isEmpty { Text(tr("Loading process table…")).font(.system(size: 11)).foregroundStyle(T.muted) }
        ForEach(model.procVM.procs.sorted{$0.cpu>$1.cpu}.prefix(5), id: \.pid) { pr in
            HStack { Text(pr.name).font(.system(size: 12)).foregroundStyle(T.ink).lineLimit(1); Spacer()
                MeterBar(value: pr.cpu/100, color: pr.cpu > 50 ? T.amber : T.accent).frame(width: 70)
                Text(String(format: "%.1f%%", pr.cpu)).font(.system(size: 11)).monospacedDigit().foregroundStyle(T.muted).frame(width: 48, alignment: .trailing)
                Text(fmtBytes(pr.memKB*1024)).font(.system(size: 11)).monospacedDigit().foregroundStyle(T.muted).frame(width: 64, alignment: .trailing) } }
    } } }
    var storagePanel: some View { Panel { VStack(alignment: .leading, spacing: 8) {
        Text(model.t("Storage")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        Text(String(format: tr("%@ free"), fmtBytes(m.diskFree))).font(.system(size: 24, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
        MeterBar(value: m.diskTotal > 0 ? 1 - Double(m.diskFree)/Double(m.diskTotal) : 0, color: T.cyan)
        Text(String(format: tr("of %@ total"), fmtBytes(m.diskTotal))).font(.system(size: 11)).foregroundStyle(T.muted)
    } } }
    var uptimePanel: some View { Panel { VStack(alignment: .leading, spacing: 4) { Text(model.t("Uptime")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        Text("\(Int(m.uptime/3600))h \(Int(m.uptime.truncatingRemainder(dividingBy: 3600)/60))m").font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink) } } }
    var processesPanel: some View { Panel { VStack(alignment: .leading, spacing: 4) { Text(model.t("Processes")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        Text("\(m.processCount)").font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink) } } }
    var memoryPanel: some View { Panel { VStack(alignment: .leading, spacing: 7) {
        HStack { Text(model.t("Memory by process")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted); Spacer(); Text(model.t("click a row to inspect")).font(.system(size: 9.5)).foregroundStyle(T.muted) }
        if model.procVM.procs.isEmpty { Text(tr("Loading process table…")).font(.system(size: 11)).foregroundStyle(T.muted) }
        ForEach(model.procVM.procs.sorted{$0.memKB>$1.memKB}.prefix(5), id: \.pid) { pr in
            Button { model.section = .processes } label: {
                HStack { Text(pr.name).font(.system(size: 12)).foregroundStyle(T.ink).lineLimit(1); Spacer()
                    MeterBar(value: m.memTotal > 0 ? Double(pr.memKB*1024)/Double(m.memTotal) : 0, color: T.cyan).frame(width: 70)
                    Text(fmtBytes(pr.memKB*1024)).font(.system(size: 11, weight: .medium)).monospacedDigit().foregroundStyle(T.ink).frame(width: 68, alignment: .trailing) }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        Text(tr("Share of total RAM per process. Opens Processes for detail and termination.")).font(.system(size: 9.5)).foregroundStyle(T.muted)
    } } }
    var batteryPanel: some View { Panel { VStack(alignment: .leading, spacing: 6) {
        Text(model.t("Power & thermal")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        HStack(spacing: 8) { Image(systemName: m.battery != nil ? "battery.75" : "powerplug").foregroundStyle(T.accent)
            Text(m.battery.map { "\(tr("Battery")) \($0)%" } ?? "\(tr(m.power)) · \(tr("No battery (desktop Mac)"))").font(.system(size: 13.5, weight: .medium)).foregroundStyle(T.ink) }
        Text(String(format: tr("This %@ draws from mains power, confirmed by the system power source."), m.model.isEmpty ? "Mac" : m.model)).font(.system(size: 10)).foregroundStyle(T.muted)
        Text(tr("Temperature · Fan · GPU: macOS exposes no public API for these on Apple Silicon, and Orbit installs no privileged helper — so they are not shown rather than estimated.")).font(.system(size: 10)).foregroundStyle(T.muted)
    } } }
    var recentPanel: some View { Panel { VStack(alignment: .leading, spacing: 8) {
        Text(model.t("Recent activity")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        if model.history.entries.isEmpty {
            EmptyState(icon: "clock.arrow.circlepath", title: model.t("No operations yet"), sub: "Cleanup and uninstall actions you confirm will be recorded here.")
        } else {
            ForEach(model.history.entries.prefix(5)) { e in
                HStack { Text(tr(e.action)).font(.system(size: 12, weight: .medium)).foregroundStyle(T.ink)
                    Text(trStatus(e.result)).font(.system(size: 11)).foregroundStyle(T.muted)
                    Spacer(); Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(T.muted) } }
        }
    } } }
    func stat(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(tr(label)).font(.system(size: 9.5)).foregroundStyle(T.muted); Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink) } }
    func quick(_ title: String, _ icon: String, _ s: Section) -> some View {
        Button { model.section = s } label: { HStack(spacing: 7) { Image(systemName: icon).foregroundStyle(T.accent); Text(title) } }
            .buttonStyle(GhostButtonStyle())
    }
}
