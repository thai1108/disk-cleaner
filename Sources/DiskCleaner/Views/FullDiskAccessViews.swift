import SwiftUI

/// Shown once, before the first scan without Full Disk Access.
struct FullDiskAccessSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.orange)
                    .frame(width: 60, height: 60)
                    .glassBackground(in: .circle, tint: .orange.opacity(0.2))
                Text("Allow Full Disk Access once")
                    .font(.title2.weight(.semibold))
            }
            Text("Without it, macOS asks separately for Desktop, Documents, Downloads, Photos and Music, and some folders can't be measured at all. Grant it once and Disk Cleaner never needs to ask again.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                Label("Open System Settings → Privacy & Security → Full Disk Access", systemImage: "1.circle.fill")
                Label("Turn on Disk Cleaner (add it with + if it isn't listed)", systemImage: "2.circle.fill")
                Label("Choose Quit & Reopen, then scan again", systemImage: "3.circle.fill")
            }
            .foregroundStyle(.secondary)
            Text("If you scan without it, those folders are skipped and shown with a lock, so macOS won't interrupt the scan.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Scan Without It") { model.scanWithoutFullDiskAccess() }
                    .glassButtonStyle()
                Button("Open System Settings") {
                    FullDiskAccess.openSettings()
                    model.targetAwaitingAccess = nil
                }
                .prominentGlassButtonStyle()
                .tint(theme.color)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(28)
        .frame(width: 500)
    }
}

struct FullDiskAccessBanner: View {
    var message = "Without Full Disk Access some folders (Mail, Safari, other apps' data…) can't be measured, and Desktop, Documents, Downloads, Photos and Music are skipped."

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Grant Full Disk Access for complete results").font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Open Settings") { FullDiskAccess.openSettings() }
                .glassButtonStyle()
        }
        .padding(16)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Compact reminder at the bottom of the sidebar.
struct FullDiskAccessCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Full Disk Access is off", systemImage: "lock.shield.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.orange)
            Text("Some folders are skipped or can't be measured.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Grant Access…") { FullDiskAccess.openSettings() }
                .glassButtonStyle()
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}
