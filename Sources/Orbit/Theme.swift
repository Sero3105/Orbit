import SwiftUI
import OrbitCore

enum T {
    static let bg = Color(red: 0.043, green: 0.055, blue: 0.067)
    static let surface = Color(red: 0.075, green: 0.094, blue: 0.122)
    static let raised = Color(red: 0.102, green: 0.129, blue: 0.169)
    static let ink = Color(red: 0.929, green: 0.949, blue: 0.961)
    static let muted = Color(red: 0.541, green: 0.592, blue: 0.647)
    static let accent = Color(red: 0.596, green: 0.761, blue: 0.408)
    static let cyan = Color(red: 0.337, green: 0.784, blue: 0.863)
    static let amber = Color(red: 0.910, green: 0.702, blue: 0.294)
    static let red = Color(red: 0.898, green: 0.376, blue: 0.361)
    static let radius: CGFloat = 10
}

struct Panel<Content: View>: View {
    var pad: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View { content.padding(pad).frame(maxWidth: .infinity, alignment: .leading)
        .background(T.surface, in: RoundedRectangle(cornerRadius: T.radius)) }
}

struct SectionTitle: View {
    var title: String; var sub: String = ""
    var body: some View { VStack(alignment: .leading, spacing: 3) {
        Text(tr(title)).font(.system(size: 28, weight: .semibold)).foregroundStyle(T.ink)
        if !sub.isEmpty { Text(tr(sub)).font(.system(size: 12)).foregroundStyle(T.muted) } } }
}

struct RingGauge: View {
    var value: Double // 0...1
    var label: String; var big: String
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        ZStack {
            Circle().stroke(T.raised, lineWidth: 9)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(T.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: value)
            VStack(spacing: 1) { Text(big).font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
                Text(label).font(.system(size: 10)).foregroundStyle(T.muted) }
        }
    }
}

struct MeterBar: View {
    var value: Double; var color: Color = T.accent; var height: CGFloat = 6
    var body: some View { GeometryReader { g in
        ZStack(alignment: .leading) { RoundedRectangle(cornerRadius: height/2).fill(T.raised)
            RoundedRectangle(cornerRadius: height/2).fill(color).frame(width: g.size.width * min(max(value,0),1)) }
    }.frame(height: height) }
}

struct Sparkline: View {
    var samples: [Double]; var maxV: Double = 100; var color: Color = T.accent
    var body: some View {
        GeometryReader { g in
            if samples.count > 1 {
                Path { p in
                    let step = g.size.width / CGFloat(samples.count - 1)
                    for (i, v) in samples.enumerated() {
                        let pt = CGPoint(x: CGFloat(i) * step, y: g.size.height - CGFloat(min(max(v,0),maxV)/maxV) * g.size.height)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }.stroke(color, lineWidth: 1.5)
            }
        }
    }
}

struct StatusChip: View {
    var text: String; var color: Color
    var body: some View { HStack(spacing: 6) { Circle().fill(color).frame(width: 7, height: 7)
        Text(tr(text)).font(.system(size: 11, weight: .medium)).foregroundStyle(T.ink) }
        .padding(.horizontal, 9).padding(.vertical, 5).background(T.raised, in: Capsule()) }
}

struct EmptyState: View {
    var icon: String; var title: String; var sub: String
    var body: some View { VStack(spacing: 8) {
        Image(systemName: icon).font(.system(size: 26)).foregroundStyle(T.muted)
        Text(tr(title)).font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink)
        Text(tr(sub)).font(.system(size: 11)).foregroundStyle(T.muted).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity).padding(.vertical, 36) }
}

struct TreemapStrip: View {
    var entries: [(name: String, size: Int64, isDir: Bool)]
    var total: Int64 { entries.reduce(0) { $0 + $1.size } }
    var body: some View {
        GeometryReader { g in
            HStack(spacing: 2) {
                ForEach(Array(entries.enumerated()), id: \.offset) { i, e in
                    let frac = total > 0 ? CGFloat(e.size) / CGFloat(total) : 0
                    let shade = max(0.82 - Double(i) * 0.055, 0.30)
                    ZStack(alignment: .bottomLeading) {
                        Rectangle().fill(T.cyan.opacity(shade))
                        if frac * g.size.width > 64 {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.name).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.95)).lineLimit(1)
                                Text(fmtBytes(e.size)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.75))
                            }.padding(6)
                        }
                    }.frame(width: max(frac * g.size.width - 2, 3))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PermissionGate: View {
    var icon: String; var title: String; var bodyText: String
    var onEnable: () -> Void; var onSkip: () -> Void
    var body: some View { Panel { VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) { Image(systemName: icon).font(.system(size: 18)).foregroundStyle(T.accent)
            Text(tr(title)).font(.system(size: 15, weight: .semibold)).foregroundStyle(T.ink) }
        Text(tr(bodyText)).font(.system(size: 12)).foregroundStyle(T.muted)
        HStack(spacing: 10) {
            Button(tr("Enable access"), action: onEnable).buttonStyle(AccentButtonStyle())
            Button(tr("Not now"), action: onSkip).buttonStyle(GhostButtonStyle())
        }
        Text(tr("Your choice is saved on this Mac and remembered between launches. You can change it later in Settings (⌘,). macOS may still show its own system prompt the first time a protected folder is read — that one is controlled by macOS, in System Settings → Privacy & Security.")).font(.system(size: 10)).foregroundStyle(T.muted)
    } } }
}

struct AccentTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(T.accent.opacity(configuration.isPressed ? 0.45 : 0.78))
            .padding(.horizontal, 6).padding(.vertical, 4)
    }
}
struct SortHead: View {
    var title: String; var active: Bool; var asc: Bool; var align: Alignment = .center; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) { Text(tr(title)).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(active ? T.ink : T.muted)
                if active { Image(systemName: asc ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .bold)).foregroundStyle(T.accent) } }
            .frame(maxWidth: .infinity, alignment: align).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.black)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(T.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 7))
    }
}
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(T.ink)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(T.raised.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 7))
    }
}
struct DangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(T.red.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 7))
    }
}

func healthStatus(_ m: Metrics) -> (String, Color) {
    if m.diskTotal > 0 && Double(m.diskFree) / Double(m.diskTotal) < 0.10 { return ("Low disk space", T.red) }
    if m.memTotal > 0 && Double(m.memUsed) / Double(m.memTotal) > 0.90 { return ("High memory pressure", T.amber) }
    if m.cpu > 85 { return ("Elevated CPU usage", T.amber) }
    return ("System normal", T.accent)
}
