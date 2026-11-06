import AppKit
import DiskCleanerCore
import SwiftUI

/// Color themes picked in Settings; Teal is the default.
enum AppTheme: String, CaseIterable, Identifiable {
    case teal, indigo, violet, coral, graphite

    static let storageKey = "theme"

    var id: Self { self }

    var name: String {
        switch self {
        case .teal: "Teal"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .coral: "Coral"
        case .graphite: "Graphite"
        }
    }

    /// sRGB components for the light and dark appearance.
    private var components: (light: SIMD3<Double>, dark: SIMD3<Double>) {
        switch self {
        case .teal: ([0.00, 0.55, 0.62], [0.25, 0.78, 0.84])
        case .indigo: ([0.35, 0.34, 0.84], [0.49, 0.48, 1.00])
        case .violet: ([0.56, 0.30, 0.85], [0.72, 0.52, 1.00])
        case .coral: ([0.93, 0.40, 0.26], [1.00, 0.55, 0.42])
        case .graphite: ([0.35, 0.38, 0.44], [0.62, 0.65, 0.71])
        }
    }

    var color: Color {
        let (light, dark) = components
        return Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
        })
    }

    /// Hue that leads the item colors; nil for a neutral theme.
    var hue: Double? {
        let rgb = components.light
        let color = NSColor(srgbRed: rgb.x, green: rgb.y, blue: rgb.z, alpha: 1)
        return color.saturationComponent > 0.25 ? Double(color.hueComponent) : nil
    }

    var palette: Palette { Palette(hues: CategoryHues.hues(leadingWith: hue)) }
}

extension EnvironmentValues {
    @Entry var theme: AppTheme = .teal
}
