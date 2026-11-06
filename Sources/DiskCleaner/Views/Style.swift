import AppKit
import DiskCleanerCore
import SwiftUI

/// Colors for a folder's items: one hue each, lighter shades for what is inside them.
struct Palette {
    let hues: [Double]

    func color(branch: Int, shade: Int, isDirectory: Bool, isLit: Bool = false) -> Color {
        let hue = hues[branch % hues.count]
        var saturation = max(0.28, 0.72 - Double(shade) * 0.08)
        var brightness = min(0.97, 0.80 + Double(shade) * 0.035)
        if !isDirectory {
            saturation *= 0.45
            brightness *= 0.92
        }
        if isLit {
            saturation = min(1, saturation + 0.12)
            brightness = min(1, brightness + 0.12)
        }
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }

    /// Color of a part of a folder's size bar; part N matches row N of the list.
    func color(for part: Breakdown.Part, isLit: Bool = false) -> Color {
        guard let node = part.node else { return Self.other(isLit: isLit) }
        return color(branch: part.id, shade: 0, isDirectory: node.isDirectory, isLit: isLit)
    }

    /// Lighter shades of a row's color for the items inside it, files included, so the
    /// row keeps one recognizable hue.
    func color(for part: Breakdown.Part, insideBranch branch: Int) -> Color {
        guard part.node != nil else { return Self.other(isLit: false).opacity(0.7) }
        return color(branch: branch, shade: part.id, isDirectory: true)
    }

    private static func other(isLit: Bool) -> Color {
        Color(white: isLit ? 0.74 : 0.64)
    }
}

extension Int64 {
    var byteString: String { formatted(.byteCount(style: .file)) }
}

extension FileNode {
    var itemSummary: String {
        guard isDirectory else { return kind == .symlink ? "Alias" : "File" }
        return fileCount == 1 ? "1 item" : "\(fileCount.formatted()) items"
    }

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: PathRules.friendlyPath(path))
    }
}

enum FullDiskAccess {
    /// Folders that only apps with Full Disk Access may list.
    private static let probes = ["Library/Safari", "Library/Mail", "Library/Messages", "Library/Cookies"]

    static var isGranted: Bool {
        let home = NSHomeDirectory()
        for probe in probes {
            let descriptor = open(home + "/" + probe, O_RDONLY | O_DIRECTORY)
            if descriptor >= 0 {
                close(descriptor)
                return true
            }
            if errno == EPERM || errno == EACCES { return false }
        }
        return true
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A horizontal bar split into proportional colored parts.
struct UsageBar: View {
    struct Part: Identifiable {
        let id = UUID()
        let value: Double
        let style: AnyShapeStyle

        init(value: Double, style: some ShapeStyle) {
            self.value = value
            self.style = AnyShapeStyle(style)
        }
    }

    let parts: [Part]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let total = max(parts.reduce(0) { $0 + $1.value }, 1)
            HStack(spacing: 1) {
                ForEach(parts) { part in
                    Rectangle()
                        .fill(part.style)
                        .frame(width: max(0, proxy.size.width * part.value / total - 1))
                }
            }
        }
        .frame(height: height)
        .clipShape(Capsule())
    }
}

extension Volume {
    /// Used, purgeable, and free space, for usage bars. `onSelection` switches to white,
    /// since the theme color would vanish on a selected sidebar row.
    func usageParts(tint: Color, onSelection: Bool = false) -> [UsageBar.Part] {
        let used = Double(usedCapacity - purgeableCapacity)
        if onSelection {
            return [
                .init(value: used, style: Color.white.opacity(0.9)),
                .init(value: Double(purgeableCapacity), style: Color.white.opacity(0.6)),
                .init(value: Double(availableCapacity), style: Color.white.opacity(0.3)),
            ]
        }
        return [
            .init(value: used, style: tint),
            .init(value: Double(purgeableCapacity), style: tint.opacity(0.4)),
            .init(value: Double(availableCapacity), style: Color.secondary.opacity(0.25)),
        ]
    }
}

/// Soft tint behind content, which also gives the glass controls something to refract.
struct Backdrop: View {
    @Environment(\.theme) private var theme

    var body: some View {
        LinearGradient(
            colors: [theme.color.opacity(0.12), theme.color.opacity(0.02), .clear],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// Liquid Glass needs macOS 26; earlier systems get a material background and standard buttons.
extension View {
    @ViewBuilder
    func glassBackground(in shape: some Shape, tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if let tint { shape.fill(tint) }
                    shape.stroke(.separator, lineWidth: 0.5)
                }
            }
        }
    }

    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func prominentGlassButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
