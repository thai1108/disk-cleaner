import DiskCleanerCore
import SwiftUI

/// Disks and folders to scan. Each keeps its results for the session.
struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            Section("Disks") {
                ForEach(model.volumes) { volume in
                    LocationRow(target: ScanTarget(volume: volume))
                        .tag(volume.scanPath)
                }
            }
            Section("Folders") {
                ForEach(model.folders, id: \.path) { folder in
                    LocationRow(target: folder)
                        .tag(folder.path)
                }
            }
            Section("Tools") {
                QuickCleanRow()
                    .tag(AppModel.quickCleanID)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                if !model.hasFullDiskAccess {
                    FullDiskAccessCard()
                }
                HStack(spacing: 8) {
                    Button { model.isChoosingFolder = true } label: {
                        Label("Scan a Folder…", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .help("Choose a folder to scan (⌘O), or drop one onto the sidebar")
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                    }
                    .help("Settings (⌘,)")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(12)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(theme.color, lineWidth: 2)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let folder = urls.first(where: \.hasDirectoryPath) else { return false }
            model.scan(ScanTarget(folder: folder))
            return true
        } isTargeted: { isDropTargeted = $0 }
    }
}

private struct LocationRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.appearsActive) private var appearsActive
    let target: ScanTarget

    private var isSelected: Bool { model.selection == target.path }

    var body: some View {
        HStack(spacing: 6) {
            Label {
                details
            } icon: {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(isSelected && appearsActive ? AnyShapeStyle(.white) : AnyShapeStyle(theme.color))
            }
            Spacer(minLength: 4)
            status
        }
        .padding(.vertical, 4)
        .themedSelection(isSelected)
        .contextMenu { menu }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(target.title)
                .lineLimit(1)
            if let volume = target.volume {
                UsageBar(parts: volume.usageParts(tint: theme.color, onSelection: isSelected && appearsActive),
                         height: 4)
                Text("\(volume.availableCapacity.byteString) free of \(volume.totalCapacity.byteString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var symbol: String {
        if let volume = target.volume { return volume.isInternal ? "internaldrive" : "externaldrive" }
        return target.path == ScanTarget.home.path ? "house" : "folder"
    }

    private var abbreviatedPath: String {
        let home = NSHomeDirectory()
        return target.path.hasPrefix(home) ? "~" + target.path.dropFirst(home.count) : target.path
    }

    @ViewBuilder
    private var status: some View {
        if model.isScanning(target.path) {
            ProgressView().controlSize(.small)
        } else if let analysis = model.finishedScans[target.path] {
            Text(analysis.totalSize.byteString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var menu: some View {
        let isScanned = model.finishedScans[target.path] != nil
        Button(isScanned ? "Rescan" : "Scan", systemImage: "arrow.clockwise") { model.scan(target) }
        Button("Open in Finder", systemImage: "folder") {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: PathRules.friendlyPath(target.path))
        }
        if target.volume == nil, target.path != ScanTarget.home.path {
            Divider()
            Button("Remove from Sidebar", systemImage: "minus.circle") { model.remove(target) }
        } else if isScanned {
            Divider()
            Button("Forget Results", systemImage: "xmark.circle") { model.remove(target) }
        }
    }
}

private struct QuickCleanRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.appearsActive) private var appearsActive

    private var isSelected: Bool { model.selection == AppModel.quickCleanID }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Clean")
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(isSelected && appearsActive ? AnyShapeStyle(.white) : AnyShapeStyle(theme.color))
        }
        .padding(.vertical, 4)
        .themedSelection(isSelected)
    }

    private var subtitle: String {
        let total = model.quickClean.totalSize
        return total > 0 ? "\(total.byteString) can be cleaned" : "Caches, logs, build data"
    }
}

private extension View {
    /// Covers the system highlight, which always uses the app's fixed accent color.
    func themedSelection(_ isSelected: Bool) -> some View {
        modifier(ThemedSelection(isSelected: isSelected))
    }
}

private struct ThemedSelection: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.appearsActive) private var appearsActive
    let isSelected: Bool

    func body(content: Content) -> some View {
        content.listRowBackground(
            isSelected
                ? RoundedRectangle(cornerRadius: 8)
                    .fill(appearsActive ? AnyShapeStyle(theme.color) : AnyShapeStyle(.quaternary))
                    .padding(.horizontal, 9)
                : nil
        )
    }
}
