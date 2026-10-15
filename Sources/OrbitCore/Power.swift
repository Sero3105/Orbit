import Foundation
import IOKit

/// Live power draw from the SMC power telemetry that macOS publishes on the
/// AppleSmartBattery IOKit node (present on Apple Silicon laptops *and* desktops).
/// Public IOKit, read-only, no root. Values refresh every few seconds.
public struct PowerReading: Equatable {
    public var systemW: Double   // what the Mac itself consumes
    public var wallW: Double     // drawn from the socket: system input + power-adapter loss (0 while on battery)
    public var onBattery: Bool
    public init(systemW: Double, wallW: Double, onBattery: Bool) { self.systemW = systemW; self.wallW = wallW; self.onBattery = onBattery }
}

public enum PowerTelemetry {
    public static func read() -> PowerReading? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard let t = IORegistryEntryCreateCFProperty(svc, "PowerTelemetryData" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { return nil }
        return reading(from: t)
    }

    /// Pure mapping from the telemetry dictionary (milliwatts) — separated for tests.
    public static func reading(from t: [String: Any]) -> PowerReading? {
        func mW(_ k: String) -> Double { (t[k] as? NSNumber)?.doubleValue ?? 0 }
        let input = mW("SystemPowerIn"), battery = mW("BatteryPower"), load = mW("SystemLoad")
        guard input > 0 || battery > 0 || load > 0 else { return nil }
        let wall = input > 0 ? input + mW("AdapterEfficiencyLoss") : 0
        return PowerReading(systemW: (load > 0 ? load : input + battery) / 1000, wallW: wall / 1000, onBattery: input == 0 && battery > 0)
    }
}

/// Wall energy actually measured while Orbit runs, bucketed per local day (Wh).
public struct EnergyLedger: Codable, Equatable {
    public var wh: [String: Double] = [:]
    public init() {}

    static func key(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public mutating func add(watts: Double, seconds: Double, at d: Date = Date()) {
        guard watts > 0, seconds > 0 else { return }
        wh[Self.key(d), default: 0] += watts * seconds / 3600
    }
    /// Wh over the last `days` calendar days including today (days = 1 → today only).
    public func total(days: Int, now: Date = Date()) -> Double {
        (0..<days).reduce(0) { sum, i in sum + (wh[Self.key(Calendar.current.date(byAdding: .day, value: -i, to: now)!)] ?? 0) }
    }
    public var allTime: Double { wh.values.reduce(0, +) }

    public static var file: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Orbit/energy.json") }
    public static func load(from f: URL = file) -> EnergyLedger { (try? JSONDecoder().decode(EnergyLedger.self, from: Data(contentsOf: f))) ?? EnergyLedger() }
    public func save(to f: URL = file) {
        try? FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: f, options: .atomic) }
    }
}

/// Cost of `wh` watt-hours at `pricePerKWh` (the €/kWh on the electricity bill).
public func energyCost(wh: Double, pricePerKWh: Double) -> Double { wh / 1000 * pricePerKWh }
