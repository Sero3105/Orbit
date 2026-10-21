// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Copyright (C) 2026 The Orbit Authors

// Renders the installer (DMG) window background in Orbit's style: a dark
// surface with faint orbit rings, the ring mark and title on top, a dashed
// orbital arrow from the app toward the Applications folder, and the install
// instruction in Italian and English. Finder places the two icons on top
// (Tools/make-dmg.sh: app at x 170, Applications at x 490, both at y 205).
// Usage: swift Tools/MakeDMGBackground.swift <output.png> [version]
import AppKit

// Window content is 660×420 pt; rendered at 2× and tagged 144 dpi so Finder
// draws it at point size on Retina and non-Retina displays alike.
let scale: CGFloat = 2
let widthPt: CGFloat = 660, heightPt: CGFloat = 420
let px = Int(widthPt * scale), py = Int(heightPt * scale)

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let version = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

// Orbit palette (docs/design-system.md).
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
let bg = rgb(0x0B0E11), surface = rgb(0x13181F), ink = rgb(0xEDF2F5), muted = rgb(0x8A97A5), accent = rgb(0xA8E04A)

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0),
      let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
rep.size = NSSize(width: widthPt, height: heightPt)  // → 144 dpi in the PNG

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
ctx.cgContext.scaleBy(x: scale, y: scale)   // draw in points, output at 2×

let full = NSRect(x: 0, y: 0, width: widthPt, height: heightPt)
// Coordinates are bottom-up; Finder's icon y = 205 from the top is this y.
let iconY = heightPt - 205
let appX: CGFloat = 170, appsX: CGFloat = 490

// Background: a soft glow around the icons fading into the app's base tone.
bg.setFill(); full.fill()
NSGradient(colors: [surface, bg])?.draw(fromCenter: NSPoint(x: widthPt / 2, y: iconY), radius: 0,
                                        toCenter: NSPoint(x: widthPt / 2, y: iconY), radius: 380, options: [])

// Faint orbit rings centered between the icons.
for (i, r) in [CGFloat(150), 230, 320, 420].enumerated() {
    let ring = NSBezierPath(ovalIn: NSRect(x: widthPt / 2 - r * 1.25, y: iconY - r * 0.62, width: r * 2.5, height: r * 1.24))
    ring.lineWidth = 1
    rgb(0xEDF2F5, 0.045 - CGFloat(i) * 0.008).setStroke()
    ring.stroke()
}

// Brand: the ring mark (sidebar geometry) beside the title.
func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, y: CGFloat, kern: CGFloat = 0) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern]
    let w = s.size(withAttributes: attrs).width
    s.draw(at: NSPoint(x: centerX - w / 2, y: y), withAttributes: attrs)
}
let titleAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 30, weight: .semibold), .foregroundColor: ink]
let titleW = "Orbit".size(withAttributes: titleAttrs).width
let markD: CGFloat = 26, gap: CGFloat = 12
let groupX = widthPt / 2 - (markD + gap + titleW) / 2
let markCenter = NSPoint(x: groupX + markD / 2, y: heightPt - 54)
let ring = NSBezierPath(ovalIn: NSRect(x: markCenter.x - markD / 2, y: markCenter.y - markD / 2, width: markD, height: markD))
ring.lineWidth = 3; accent.setStroke(); ring.stroke()
let dot: CGFloat = 6.5
accent.setFill()
NSBezierPath(ovalIn: NSRect(x: markCenter.x + 9.5 - dot / 2, y: markCenter.y + 9.5 - dot / 2, width: dot, height: dot)).fill()
"Orbit".draw(at: NSPoint(x: groupX + markD + gap, y: heightPt - 72), withAttributes: titleAttrs)
drawText("Il tuo Mac, in equilibrio.  ·  Your Mac, in balance.", size: 12, weight: .regular, color: muted,
         centerX: widthPt / 2, y: heightPt - 100)

// Orbital arrow: a dashed arc from the app to Applications, with a solid head.
let start = NSPoint(x: appX + 84, y: iconY + 8), end = NSPoint(x: appsX - 88, y: iconY + 8)
let arc = NSBezierPath()
arc.move(to: start)
arc.curve(to: end, controlPoint1: NSPoint(x: start.x + 40, y: iconY + 46), controlPoint2: NSPoint(x: end.x - 40, y: iconY + 46))
arc.lineWidth = 3
arc.lineCapStyle = .round
arc.setLineDash([2, 9], count: 2, phase: 0)
accent.withAlphaComponent(0.95).setStroke()
arc.stroke()
// The head follows the arc's tangent at its end (end − last control point).
let tangent = atan2(end.y - (iconY + 46), end.x - (end.x - 40))
func arm(_ turn: CGFloat) -> NSPoint {
    NSPoint(x: end.x + 15 * cos(tangent + turn), y: end.y + 15 * sin(tangent + turn))
}
let head = NSBezierPath()
head.move(to: arm(.pi * 0.8))
head.line(to: end)
head.line(to: arm(-.pi * 0.8))
head.lineWidth = 3.2; head.lineCapStyle = .round; head.lineJoinStyle = .round
accent.setStroke(); head.stroke()

// Instruction panel at the bottom.
let panel = NSRect(x: 110, y: 26, width: widthPt - 220, height: 62)
let panelPath = NSBezierPath(roundedRect: panel, xRadius: 12, yRadius: 12)
rgb(0x1A212B, 0.85).setFill(); panelPath.fill()
rgb(0xEDF2F5, 0.06).setStroke(); panelPath.lineWidth = 1; panelPath.stroke()
drawText("Trascina Orbit nella cartella Applicazioni", size: 14, weight: .semibold, color: ink, centerX: widthPt / 2, y: 60)
drawText("Drag Orbit to the Applications folder", size: 11.5, weight: .regular, color: muted, centerX: widthPt / 2, y: 40)
if !version.isEmpty {
    drawText("v\(version)", size: 10, weight: .medium, color: rgb(0x8A97A5, 0.7), centerX: widthPt - 40, y: 10)
}

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: out))
    print("dmg background written to \(out)")
} catch {
    print("failed: \(error)")
    exit(1)
}
