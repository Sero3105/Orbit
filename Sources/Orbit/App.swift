import SwiftUI
import OrbitCore

enum Section: String, CaseIterable { case dashboard = "Dashboard", cleanup = "Cleanup", disk = "Disk Analyzer", apps = "Applications", maintenance = "Maintenance", processes = "Processes", history = "History"
    var icon: String { switch self { case .dashboard: return "gauge.with.dots.needle.33percent"; case .cleanup: return "sparkles"; case .disk: return "externaldrive"; case .apps: return "square.grid.2x2"; case .maintenance: return "wrench.and.screwdriver"; case .processes: return "list.bullet.rectangle"; case .history: return "clock.arrow.circlepath" } } }

@main struct OrbitApp: App {
    @ObservedObject var model = Model.shared
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).preferredColorScheme(.dark).frame(minWidth: 920, minHeight: 580) }
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
    @Published var section: Section = .dashboard
    @Published var cpuSamples: [Double] = []
    @Published var memSamples: [Double] = []
    init() { Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in DispatchQueue.global().async { let m = SystemMetrics.sample(); DispatchQueue.main.async { guard let self else { return }; self.metrics = m; self.cpuSamples.append(m.cpu); self.memSamples.append(m.memTotal > 0 ? Double(m.memUsed)/Double(m.memTotal)*100 : 0); if self.cpuSamples.count > 45 { self.cpuSamples.removeFirst() ; self.memSamples.removeFirst() } } } } }
    var allowedRoots: [String] { CleanupScanner().categories().map(\.root) + [NSHomeDirectory()+"/Applications", "/Applications"] }
    func reloadHistory() { history = HistoryStore() }
}

struct ContentView: View {
    @EnvironmentObject var model: Model
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 212)
            Rectangle().fill(T.surface).frame(width: 1)
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(T.bg)
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                ZStack { Circle().stroke(T.accent, lineWidth: 2.5).frame(width: 22, height: 22)
                    Circle().fill(T.accent).frame(width: 5, height: 5).offset(x: 8, y: -8) }
                VStack(alignment: .leading, spacing: 0) { Text("Orbit").font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink)
                    Text("Your Mac, in balance.").font(.system(size: 9)).foregroundStyle(T.muted) }
            }.padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 18)
            Text("Monitor").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted).padding(.horizontal, 16).padding(.bottom, 4)
            navItem(.dashboard); navItem(.processes)
            Text("Manage").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            navItem(.cleanup); navItem(.disk); navItem(.apps); navItem(.maintenance)
            Text("Record").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.muted).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 4)
            navItem(.history)
            Spacer()
            StatusChip(text: healthStatus(model.metrics).0, color: healthStatus(model.metrics).1).padding(14)
        }.background(T.bg)
    }
    func navItem(_ s: Section) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { model.section = s } } label: {
            HStack(spacing: 9) {
                Image(systemName: s.icon).font(.system(size: 13)).frame(width: 18)
                    .foregroundStyle(model.section == s ? T.accent : T.muted)
                Text(s.rawValue).font(.system(size: 12.5, weight: model.section == s ? .semibold : .regular))
                    .foregroundStyle(model.section == s ? T.ink : T.muted)
                Spacer()
            }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
            .background(model.section == s ? T.raised : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }
    @ViewBuilder var detail: some View {
        switch model.section {
        case .dashboard: DashboardView()
        case .cleanup: CleanupView()
        case .disk: DiskView()
        case .apps: AppsView()
        case .maintenance: MaintenanceView()
        case .processes: ProcessesView()
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
                SectionTitle(title: "Dashboard", sub: "Live system state from native macOS APIs. Nothing here is simulated.")
                Spacer()
                StatusChip(text: "Live · updating every 2s", color: T.accent)
            }
            HStack(alignment: .top, spacing: 16) {
                Panel { VStack(alignment: .leading, spacing: 10) {
                    Text("Processor").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                    HStack(spacing: 18) {
                        RingGauge(value: m.cpu/100, label: "CPU", big: String(format: "%.0f%%", m.cpu)).frame(width: 118, height: 118)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Memory").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                            Text(fmtBytes(m.memUsed)).font(.system(size: 24, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
                            Text("of \(fmtBytes(m.memTotal)) used").font(.system(size: 11)).foregroundStyle(T.muted)
                            MeterBar(value: m.memTotal > 0 ? Double(m.memUsed)/Double(m.memTotal) : 0, color: T.cyan).frame(width: 170)
                        }
                    }
                    Text("Session trend — real samples since launch, 2s interval").font(.system(size: 10)).foregroundStyle(T.muted).padding(.top, 4)
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 3) { Text("CPU").font(.system(size: 9)).foregroundStyle(T.muted); Sparkline(samples: model.cpuSamples).frame(width: 190, height: 30) }
                        VStack(alignment: .leading, spacing: 3) { Text("Memory %").font(.system(size: 9)).foregroundStyle(T.muted); Sparkline(samples: model.memSamples, color: T.cyan).frame(width: 190, height: 30) }
                    }
                } }
                VStack(spacing: 16) {
                    Panel { VStack(alignment: .leading, spacing: 8) {
                        Text("Storage").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                        Text("\(fmtBytes(m.diskFree)) free").font(.system(size: 24, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
                        MeterBar(value: m.diskTotal > 0 ? 1 - Double(m.diskFree)/Double(m.diskTotal) : 0, color: T.cyan)
                        Text("of \(fmtBytes(m.diskTotal)) total").font(.system(size: 11)).foregroundStyle(T.muted)
                    } }
                    HStack(spacing: 16) {
                        Panel { VStack(alignment: .leading, spacing: 4) { Text("Uptime").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                            Text("\(Int(m.uptime/3600))h \(Int(m.uptime.truncatingRemainder(dividingBy: 3600)/60))m").font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink) } }
                        Panel { VStack(alignment: .leading, spacing: 4) { Text("Processes").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                            Text("\(m.processCount)").font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink) } }
                    }
                    Panel { VStack(alignment: .leading, spacing: 4) {
                        Text("Battery · Temperature · Fan · GPU").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                        Text(m.battery.map { "\($0)%" } ?? "Unavailable").font(.system(size: 15, weight: .medium)).foregroundStyle(T.ink)
                        Text("No public API without a privileged helper — shown unavailable, never invented.").font(.system(size: 10)).foregroundStyle(T.muted)
                    } }
                }.frame(maxWidth: .infinity)
            }
            Panel { VStack(alignment: .leading, spacing: 10) {
                Text("Quick actions").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                HStack(spacing: 10) {
                    quick("Scan for cleanup", "sparkles", .cleanup); quick("Analyze disk", "externaldrive", .disk)
                    quick("Review applications", "square.grid.2x2", .apps); quick("Inspect processes", "list.bullet.rectangle", .processes); quick("Maintenance", "wrench.and.screwdriver", .maintenance)
                }
            } }
            Panel { VStack(alignment: .leading, spacing: 8) {
                Text("Recent activity").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
                if model.history.entries.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: "No operations yet", sub: "Cleanup and uninstall actions you confirm will be recorded here.")
                } else {
                    ForEach(model.history.entries.prefix(5)) { e in
                        HStack { Text(e.action).font(.system(size: 12, weight: .medium)).foregroundStyle(T.ink)
                            Text(e.result).font(.system(size: 11)).foregroundStyle(T.muted)
                            Spacer(); Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(T.muted) }
                    }
                }
            } }
        }.padding(22) }.background(T.bg)
    }
    func quick(_ title: String, _ icon: String, _ s: Section) -> some View {
        Button { model.section = s } label: { HStack(spacing: 7) { Image(systemName: icon).foregroundStyle(T.accent); Text(title) } }
            .buttonStyle(GhostButtonStyle())
    }
}
