import SwiftUI
import OrbitCore

struct EnergyView: View {
    @EnvironmentObject var model: Model
    var watts: Double { model.power.map { $0.wallW > 0 ? $0.wallW : $0.systemW } ?? 0 }
    var price: Double { model.kwhPrice }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                SectionTitle(title: "Energy", sub: "Measured power from the Mac's own power telemetry (SMC, read through IOKit). Nothing is estimated.")
                Spacer()
                StatusChip(text: "Live · updating every 2s", color: T.accent)
            }
            if let p = model.power {
                HStack(alignment: .top, spacing: 16) { nowPanel(p); pricePanel }
                projectionPanel
                measuredPanel
            } else {
                Panel { EmptyState(icon: "bolt.slash", title: "Power telemetry unavailable", sub: "This Mac does not publish power telemetry, so Orbit shows nothing rather than a guess.") }
            }
        }.padding(22) }.background(T.bg)
    }

    func nowPanel(_ p: PowerReading) -> some View { Panel { VStack(alignment: .leading, spacing: 8) {
        Text(tr("Power now")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(String(format: "%.1f", watts)).font(.system(size: 40, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
            Text("W").font(.system(size: 16, weight: .medium)).foregroundStyle(T.muted)
        }
        Sparkline(samples: model.wattSamples, color: T.amber).frame(height: 36)
        HStack(spacing: 22) {
            stat("Mac consumption", String(format: "%.1f W", p.systemW))
            stat("From the wall", p.onBattery ? tr("On battery") : String(format: "%.1f W", p.wallW))
        }
        Text(tr("“From the wall” adds the power adapter's own loss — it is what the electricity meter counts.")).font(.system(size: 10)).foregroundStyle(T.muted)
    } } }

    var pricePanel: some View { Panel { VStack(alignment: .leading, spacing: 8) {
        Text(tr("Electricity price")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        HStack(spacing: 6) {
            TextField("0.25", value: $model.kwhPrice, format: .number.precision(.fractionLength(0...4)))
                .textFieldStyle(.roundedBorder).frame(width: 90).monospacedDigit()
            Text("\(currencySymbol)/kWh").font(.system(size: 13, weight: .medium)).foregroundStyle(T.ink)
        }
        Text(tr("Find it on your electricity bill: the price per kWh (kilowatt-hour). Use the all-in price (energy + network + taxes) for the real cost.")).font(.system(size: 10.5)).foregroundStyle(T.muted)
        if price <= 0 { Text(tr("Enter a price to see costs.")).font(.system(size: 11, weight: .medium)).foregroundStyle(T.amber) }
    } }.frame(maxWidth: 320) }

    var projectionPanel: some View { Panel { VStack(alignment: .leading, spacing: 10) {
        Text(tr("If it keeps running at the current draw")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        HStack(spacing: 10) {
            ForEach([("Per second", 1.0 / 3600), ("Per hour", 1), ("Per day", 24), ("Per week", 168), ("Per month (30 d)", 720)], id: \.0) { label, hours in
                tile(label, wh: watts * hours, digits: 2)
            }
        }
    } } }

    var measuredPanel: some View { Panel { VStack(alignment: .leading, spacing: 10) {
        Text(tr("Actually spent — measured while Orbit was running")).font(.system(size: 11, weight: .semibold)).foregroundStyle(T.muted)
        HStack(spacing: 10) {
            tile("Today", wh: model.energy.total(days: 1), digits: 2)
            tile("Last 7 days", wh: model.energy.total(days: 7), digits: 2)
            tile("Last 30 days", wh: model.energy.total(days: 30), digits: 2)
            tile("All time", wh: model.energy.allTime, digits: 2)
        }
        Text(tr("Energy is counted only while Orbit is open (window or menu bar). Stored locally in ~/Library/Application Support/Orbit/energy.json.")).font(.system(size: 10)).foregroundStyle(T.muted)
    } } }

    func tile(_ label: String, wh: Double, digits: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tr(label)).font(.system(size: 10)).foregroundStyle(T.muted)
            Text(price > 0 ? money(energyCost(wh: wh, pricePerKWh: price), digits: digits) : "—").font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink)
            Text(wh >= 1000 ? String(format: "%.2f kWh", wh / 1000) : String(format: wh < 1 ? "%.3f Wh" : "%.1f Wh", wh)).font(.system(size: 10.5)).monospacedDigit().foregroundStyle(T.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(T.raised, in: RoundedRectangle(cornerRadius: 8))
    }

    func stat(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 2) {
        Text(tr(label)).font(.system(size: 9.5)).foregroundStyle(T.muted)
        Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(T.ink) } }

    var currencySymbol: String { Locale.current.currencySymbol ?? "€" }
    /// At least `digits` decimals, more for tiny amounts so they never read as 0,00 (two significant figures).
    func money(_ v: Double, digits: Int) -> String {
        let d = v > 0 ? max(digits, min(8, Int(-floor(log10(v))) + 1)) : digits
        return v.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR").precision(.fractionLength(d)))
    }
}
