import SwiftUI

/// The app's Settings window (⌘,).
struct SettingsView: View {
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .teal

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(AppTheme.allCases) { option in
                        ThemeSwatch(theme: option, isSelected: option == theme) {
                            withAnimation(.smooth(duration: 0.25)) { theme = option }
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Theme")
            } footer: {
                Text("Colors the sidebar selection, buttons, size bars and backgrounds.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .tint(theme.color)
        .environment(\.theme, theme)
    }
}

/// A miniature of the app in one theme: a selected sidebar row, a size bar, and a button.
private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: 84, height: 62)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? theme.color : Color.secondary.opacity(0.3),
                                          lineWidth: isSelected ? 3 : 1)
                    }
                HStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.color)
                    }
                    Text(theme.name)
                        .fontWeight(isSelected ? .semibold : .regular)
                }
                .font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var preview: some View {
        let palette = theme.palette
        return VStack(alignment: .leading, spacing: 6) {
            Capsule()
                .fill(theme.color)
                .frame(width: 38, height: 9)
            HStack(spacing: 1.5) {
                ForEach(0..<3) { index in
                    Rectangle()
                        .fill(palette.color(branch: index, shade: 0, isDirectory: true))
                        .frame(width: [26, 14, 8][index])
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            Capsule()
                .fill(theme.color)
                .frame(width: 30, height: 12)
                .overlay(Capsule().fill(.white.opacity(0.85)).frame(width: 16, height: 3))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [theme.color.opacity(0.22), theme.color.opacity(0.04)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
