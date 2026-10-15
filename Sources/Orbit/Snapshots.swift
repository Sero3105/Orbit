import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// `Orbit --screenshots <dir>` renders each section offscreen to PNG plus an animated tour.gif
/// (used for the README; needs no Screen Recording permission). Combine with defaults
/// overrides, e.g. `-orbit.lang it -orbit.access.apps YES -orbit.kwhPrice 0.3`. Add `--demo` for fictional data
/// (README media: `Orbit --demo --screenshots docs/media -orbit.lang en -orbit.access.cleanup YES -orbit.access.apps YES -AppleLocale en_IE`).
enum Snapshots {
    static func runIfRequested(model: Model) {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let host = NSHostingView(rootView: ContentView().environmentObject(model).preferredColorScheme(.dark))
        let win = NSWindow(contentRect: NSRect(x: -20000, y: 0, width: 1240, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host; win.orderBack(nil)
        let plan: [(Section, String)] = [(.dashboard, "dashboard"), (.energy, "energy"), (.processes, "processes"), (.cleanup, "cleanup"), (.apps, "applications"), (.maintenance, "maintenance")]
        var frames: [CGImage] = []
        if isDemo { Demo.load(into: model) } else { model.cleanupVM.scan(); model.appsVM.load(); model.procVM.load() }
        func shoot(_ k: Int) {
            guard k < plan.count else { writeGIF(frames, to: dir.appendingPathComponent("tour.gif")); exit(0) }
            model.section = plan[k].0
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                host.layoutSubtreeIfNeeded()
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return shoot(k + 1) }
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(plan[k].1 + ".png"))
                if let cg = rep.cgImage { frames.append(cg) }
                shoot(k + 1)
            }
        }
        // Live mode: let samples accumulate so sparklines and the power ledger have data.
        DispatchQueue.main.asyncAfter(deadline: .now() + (isDemo ? 1 : 20)) { shoot(0) }
    }

    static func writeGIF(_ frames: [CGImage], to url: URL) {
        guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { return }
        CGImageDestinationSetProperties(d, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for f in frames { CGImageDestinationAddImage(d, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 2.5]] as CFDictionary) }
        CGImageDestinationFinalize(d)
    }
}
