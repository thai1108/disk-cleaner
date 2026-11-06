/// Hues that tell a folder's items apart, optionally led by a theme's hue so the
/// largest item matches the app's color.
public enum CategoryHues {
    public static let base: [Double] = [0.58, 0.36, 0.12, 0.02, 0.79, 0.49, 0.67, 0.92, 0.24, 0.07]

    /// `accent` first, then the base hues that are not too close to it to tell apart.
    public static func hues(leadingWith accent: Double?) -> [Double] {
        guard let accent else { return base }
        return [accent] + base.filter { min(abs($0 - accent), 1 - abs($0 - accent)) > 0.06 }
    }
}
