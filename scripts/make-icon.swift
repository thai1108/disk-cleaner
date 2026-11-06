// Renders the app icon (an open hard drive under a magnifying glass) into an .icns file.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// Everything is drawn in a 1024-point canvas and scaled to each icon size.

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func hex(_ v: UInt32, _ a: CGFloat = 1) -> CGColor {
    rgb(CGFloat((v >> 16) & 0xFF) / 255, CGFloat((v >> 8) & 0xFF) / 255, CGFloat(v & 0xFF) / 255, a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil) }

let tile = CGRect(x: 100, y: 100, width: 824, height: 824)

func background(_ ctx: CGContext, top: UInt32, bottom: UInt32) {
    let shape = rounded(tile, 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: hex(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(hex(bottom)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(gradient([hex(top), hex(bottom)]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    // Soft light from the top.
    ctx.drawRadialGradient(gradient([hex(0xFFFFFF, 0.22), hex(0xFFFFFF, 0)]),
                           startCenter: CGPoint(x: 512, y: 960), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 960), endRadius: 560, options: [])
    ctx.restoreGState()
    // Hairline rim.
    ctx.addPath(rounded(tile.insetBy(dx: 1.5, dy: 1.5), 184)); ctx.setStrokeColor(hex(0xFFFFFF, 0.18)); ctx.setLineWidth(3); ctx.strokePath()
}

/// An open hard drive seen from above: aluminium case, mirror platter, actuator arm.
func openDrive(_ ctx: CGContext, frame: CGRect) {
    let caseRadius = min(frame.width, frame.height) * 0.09
    let body = rounded(frame, caseRadius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 40, color: hex(0x000000, 0.45))
    ctx.addPath(body); ctx.setFillColor(hex(0xC9D1D8)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(gradient([hex(0xF4F6F8), hex(0xD5DCE2), hex(0xB9C2CA)], [0, 0.5, 1]),
                           start: CGPoint(x: frame.minX, y: frame.maxY), end: CGPoint(x: frame.maxX, y: frame.minY), options: [])
    ctx.restoreGState()
    ctx.addPath(rounded(frame.insetBy(dx: 2, dy: 2), caseRadius - 2)); ctx.setStrokeColor(hex(0xFFFFFF, 0.7)); ctx.setLineWidth(3); ctx.strokePath()

    // Recessed well holding the platter and the arm.
    let inset = min(frame.width, frame.height) * 0.07
    let well = frame.insetBy(dx: inset, dy: inset)
    let wellPath = rounded(well, caseRadius * 0.7)
    ctx.saveGState()
    ctx.addPath(wellPath); ctx.clip()
    ctx.drawLinearGradient(gradient([hex(0xA7B1BA), hex(0xC6CED5)]), start: CGPoint(x: well.midX, y: well.maxY), end: CGPoint(x: well.midX, y: well.minY), options: [])
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(wellPath); ctx.clip()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: hex(0x000000, 0.35))
    ctx.addRect(well.insetBy(dx: -40, dy: -40)); ctx.addPath(wellPath); ctx.setFillColor(hex(0x8E99A3)); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // Screws in the case corners.
    let screwR = inset * 0.28
    for (x, y) in [(frame.minX + inset / 2, frame.minY + inset / 2), (frame.maxX - inset / 2, frame.minY + inset / 2),
                   (frame.minX + inset / 2, frame.maxY - inset / 2), (frame.maxX - inset / 2, frame.maxY - inset / 2)] {
        ctx.addEllipse(in: CGRect(x: x - screwR, y: y - screwR, width: 2 * screwR, height: 2 * screwR))
        ctx.setFillColor(hex(0x9AA5AF)); ctx.fillPath()
        ctx.setStrokeColor(hex(0x6E7A85)); ctx.setLineWidth(screwR * 0.35)
        ctx.move(to: CGPoint(x: x - screwR * 0.55, y: y + screwR * 0.55)); ctx.addLine(to: CGPoint(x: x + screwR * 0.55, y: y - screwR * 0.55)); ctx.strokePath()
    }

    // Platter, placed toward the far end of the well.
    let r = min(well.width, well.height) * 0.46
    let isPortrait = frame.height > frame.width
    let c = isPortrait ? CGPoint(x: well.midX, y: well.maxY - r - well.width * 0.04)
                       : CGPoint(x: well.minX + r + well.height * 0.04, y: well.midY)
    let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: hex(0x000000, 0.35))
    ctx.addEllipse(in: disc); ctx.setFillColor(hex(0xB8C2CA)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: disc); ctx.clip()
    ctx.drawLinearGradient(gradient([hex(0xFAFBFC), hex(0xA9B4BE), hex(0xEEF2F5), hex(0x96A2AD)], [0, 0.38, 0.62, 1]),
                           start: CGPoint(x: disc.minX, y: disc.maxY), end: CGPoint(x: disc.maxX, y: disc.minY), options: [])
    for angle in [CGFloat.pi * 0.28, CGFloat.pi * 1.28] {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: angle)
        ctx.move(to: .zero); ctx.addArc(center: .zero, radius: r, startAngle: -0.2, endAngle: 0.2, clockwise: false); ctx.closePath()
        ctx.setFillColor(hex(0xFFFFFF, 0.5)); ctx.fillPath()
        ctx.restoreGState()
    }
    for i in stride(from: r * 0.32, to: r, by: r * 0.05) {
        ctx.addEllipse(in: CGRect(x: c.x - i, y: c.y - i, width: 2 * i, height: 2 * i))
        ctx.setStrokeColor(hex(0x6F7B86, 0.10)); ctx.setLineWidth(2); ctx.strokePath()
    }
    ctx.restoreGState()
    ctx.addEllipse(in: disc.insetBy(dx: 1.5, dy: 1.5)); ctx.setStrokeColor(hex(0x6F7B86, 0.7)); ctx.setLineWidth(3); ctx.strokePath()
    // Spindle.
    let hubR = r * 0.24
    let hub = CGRect(x: c.x - hubR, y: c.y - hubR, width: 2 * hubR, height: 2 * hubR)
    ctx.saveGState()
    ctx.addEllipse(in: hub); ctx.clip()
    ctx.drawLinearGradient(gradient([hex(0xFFFFFF), hex(0x8F9BA6)]), start: CGPoint(x: hub.minX, y: hub.maxY), end: CGPoint(x: hub.maxX, y: hub.minY), options: [])
    ctx.restoreGState()
    ctx.addEllipse(in: hub); ctx.setStrokeColor(hex(0x6F7B86)); ctx.setLineWidth(3); ctx.strokePath()
    for k in 0..<6 {
        let a = CGFloat(k) * .pi / 3
        let p = CGPoint(x: c.x + cos(a) * hubR * 0.6, y: c.y + sin(a) * hubR * 0.6)
        ctx.addEllipse(in: CGRect(x: p.x - hubR * 0.1, y: p.y - hubR * 0.1, width: hubR * 0.2, height: hubR * 0.2)); ctx.setFillColor(hex(0x6F7B86)); ctx.fillPath()
    }

    // Actuator arm from the near corner, its head resting on the platter.
    let pivot = isPortrait ? CGPoint(x: well.minX + well.width * 0.2, y: well.minY + well.width * 0.2)
                           : CGPoint(x: well.maxX - well.height * 0.2, y: well.minY + well.height * 0.22)
    let head = CGPoint(x: c.x + r * 0.42, y: c.y - r * 0.38)
    let angle = atan2(head.y - pivot.y, head.x - pivot.x)
    let length = hypot(head.x - pivot.x, head.y - pivot.y)
    let w = r * 0.13
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: hex(0x000000, 0.45))
    ctx.translateBy(x: pivot.x, y: pivot.y); ctx.rotate(by: angle)
    let arm = CGMutablePath()
    arm.move(to: CGPoint(x: 0, y: -w)); arm.addLine(to: CGPoint(x: length, y: -w * 0.35))
    arm.addLine(to: CGPoint(x: length, y: w * 0.35)); arm.addLine(to: CGPoint(x: 0, y: w)); arm.closeSubpath()
    ctx.addPath(arm); ctx.setFillColor(hex(0x2C343A)); ctx.fillPath()
    ctx.addPath(rounded(CGRect(x: length - w * 0.5, y: -w * 0.55, width: w * 1.2, height: w * 1.1), w * 0.25)); ctx.setFillColor(hex(0x161B1F)); ctx.fillPath()
    ctx.restoreGState()
    let pivotR = r * 0.2
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: hex(0x000000, 0.4))
    ctx.addEllipse(in: CGRect(x: pivot.x - pivotR, y: pivot.y - pivotR, width: 2 * pivotR, height: 2 * pivotR)); ctx.setFillColor(hex(0x39424A)); ctx.fillPath()
    ctx.restoreGState()
    ctx.addEllipse(in: CGRect(x: pivot.x - pivotR * 0.45, y: pivot.y - pivotR * 0.45, width: pivotR * 0.9, height: pivotR * 0.9)); ctx.setFillColor(hex(0xA2ADB7)); ctx.fillPath()
}

func magnifier(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
    let ring: CGFloat = radius * 0.24
    // Handle.
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: -.pi / 4)
    let handle = CGRect(x: radius + ring * 0.2, y: -ring * 0.62, width: radius * 1.05, height: ring * 1.24)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: hex(0x000000, 0.4))
    ctx.addPath(rounded(handle, ring * 0.62)); ctx.setFillColor(hex(0x1E2428)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: -.pi / 4)
    ctx.addPath(rounded(handle, ring * 0.62)); ctx.clip()
    ctx.drawLinearGradient(gradient([hex(0x56616B), hex(0x1C2226)]), start: CGPoint(x: 0, y: ring), end: CGPoint(x: 0, y: -ring), options: [])
    ctx.restoreGState()
    // Glass.
    let lens = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
    ctx.saveGState()
    ctx.addEllipse(in: lens); ctx.clip()
    ctx.setFillColor(hex(0xE9FBFD, 0.28)); ctx.fill(lens)
    ctx.drawLinearGradient(gradient([hex(0xFFFFFF, 0.55), hex(0xFFFFFF, 0)]),
                           start: CGPoint(x: lens.minX, y: lens.maxY), end: CGPoint(x: lens.midX, y: lens.midY), options: [])
    ctx.restoreGState()
    // Ring.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: hex(0x000000, 0.35))
    ctx.addEllipse(in: lens); ctx.setStrokeColor(hex(0x2A3136)); ctx.setLineWidth(ring); ctx.strokePath()
    ctx.restoreGState()
    ctx.addEllipse(in: lens.insetBy(dx: -ring * 0.25, dy: -ring * 0.25)); ctx.setStrokeColor(hex(0x6B7781, 0.9)); ctx.setLineWidth(ring * 0.18); ctx.strokePath()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    background(ctx, top: 0x3CC3CC, bottom: 0x0B6A78)
    openDrive(ctx, frame: CGRect(x: 232, y: 170, width: 470, height: 660))
    magnifier(ctx, center: CGPoint(x: 668, y: 330), radius: 132)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output]
try iconutil.run()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
