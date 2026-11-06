import DiskCleanerCore
import SwiftUI

/// A disk or folder that has not been scanned yet: what it holds and a big Scan button.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let target: ScanTarget

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if let volume = target.volume {
                        CapacityCard(volume: volume)
                    }
                    VStack(spacing: 10) {
                        Button { model.scan(target) } label: {
                            Label("Scan \(target.title)", systemImage: "magnifyingglass")
                                .padding(.horizontal, 18)
                        }
                        .prominentGlassButtonStyle()
                        .tint(theme.color)
                        .controlSize(.extraLarge)
                        .keyboardShortcut(.defaultAction)
                        Text("Scanning only reads sizes. Nothing is removed until you delete it yourself.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if !model.hasFullDiskAccess {
                        FullDiskAccessBanner()
                            .frame(maxWidth: 560)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
        .background(Backdrop())
        .navigationTitle(target.title)
        .navigationSubtitle(target.volume.map { "\($0.format) · \($0.totalCapacity.byteString)" } ?? "Folder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Open in Finder", systemImage: "folder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PathRules.friendlyPath(target.path))
                }
                .help("Open \(target.title) in Finder")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(theme.color)
                .frame(width: 88, height: 88)
                .glassBackground(in: .circle)
            VStack(spacing: 4) {
                Text(target.title)
                    .font(.largeTitle.weight(.bold))
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var symbol: String {
        if let volume = target.volume { return volume.isInternal ? "internaldrive.fill" : "externaldrive.fill" }
        return target.path == ScanTarget.home.path ? "house.fill" : "folder.fill"
    }

    private var subtitle: String {
        if let volume = target.volume {
            return "\(volume.usedCapacity.byteString) used of \(volume.totalCapacity.byteString)"
        }
        return PathRules.friendlyPath(target.path)
    }
}

/// Free space up front, then a bar of used, purgeable, and free space.
private struct CapacityCard: View {
    @Environment(\.theme) private var theme
    let volume: Volume

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(volume.availableCapacity.byteString)
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                Text("available")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(volume.totalCapacity.byteString) total")
                    .foregroundStyle(.secondary)
            }
            UsageBar(parts: volume.usageParts(tint: theme.color), height: 26)
            CapacityLegend(volume: volume)
        }
        .padding(20)
        .frame(maxWidth: 580)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator.opacity(0.6)))
    }
}

private struct CapacityLegend: View {
    @Environment(\.theme) private var theme
    let volume: Volume

    var body: some View {
        HStack(spacing: 28) {
            item("Used", volume.usedCapacity - volume.purgeableCapacity, theme.color)
            if volume.purgeableCapacity > 0 {
                item("Purgeable", volume.purgeableCapacity, theme.color.opacity(0.4))
            }
            item("Free", volume.availableCapacity, Color.secondary.opacity(0.25))
        }
    }

    private func item(_ title: String, _ bytes: Int64, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(bytes.byteString).font(.headline.monospacedDigit())
            }
        }
    }
}
