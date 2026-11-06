import DiskCleanerCore
import SwiftUI

extension FileKind {
    var title: String {
        switch self {
        case .video: "Videos"
        case .archive: "Archives"
        case .diskImage: "Disk Images"
        case .installer: "Installers"
        case .application: "Apps"
        }
    }

    var symbol: String {
        switch self {
        case .video: "film"
        case .archive: "doc.zipper"
        case .diskImage: "opticaldiscdrive"
        case .installer: "shippingbox"
        case .application: "app"
        }
    }
}

/// Switches the list between the focused folder's contents and its largest files.
struct ListModeBar: View {
    @Environment(\.theme) private var theme
    @Bindable var analysis: Analysis

    var body: some View {
        HStack(spacing: 12) {
            Picker("Show", selection: $analysis.listMode) {
                Text("Contents").tag(Analysis.ListMode.contents)
                Text("Largest Files").tag(Analysis.ListMode.largest)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            if analysis.listMode == .largest {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", systemImage: "square.grid.2x2", kind: nil)
                        ForEach(FileKind.allCases, id: \.self) { kind in
                            chip(kind.title, systemImage: kind.symbol, kind: kind)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private func chip(_ title: String, systemImage: String, kind: FileKind?) -> some View {
        let isSelected = analysis.largestKind == kind
        return Button {
            analysis.largestKind = kind
        } label: {
            Label(title, systemImage: systemImage)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(isSelected ? AnyShapeStyle(theme.color) : AnyShapeStyle(.quinary), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The largest files and packages anywhere under the focused folder.
struct LargestItemsList: View {
    @Bindable var analysis: Analysis
    @State private var selection: Set<FileNode.ID> = []
    @FocusState private var isFocused: Bool

    var body: some View {
        let items = analysis.largestItems
        let largest = max(items.first?.size ?? 1, 1)

        List(selection: $selection) {
            ForEach(items) { node in
                LargestItemRow(
                    node: node,
                    location: location(of: node),
                    fraction: Double(node.size) / Double(largest),
                    isInCleanup: analysis.isInCleanup(node),
                    analysis: analysis
                )
                .tag(node.id)
                .itemProvider {
                    guard analysis.canDelete(node) else { return nil }
                    return NSItemProvider(object: URL(fileURLWithPath: node.path) as NSURL)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // See ItemList: selecting a row must also make the list key.
        .focused($isFocused)
        .onChange(of: selection) {
            if !selection.isEmpty { isFocused = true }
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let nodes = items.filter { ids.contains($0.id) }
            if nodes.count == 1, let node = nodes.first {
                NodeMenu(node: node, analysis: analysis)
            } else if !nodes.isEmpty {
                Button("Add \(nodes.count) Items to Cleanup List", systemImage: "tray.and.arrow.down") {
                    nodes.forEach(analysis.addToCleanup)
                }
                Button("Move \(nodes.count) Items to Trash", systemImage: "trash") {
                    Task { await analysis.moveToTrash(nodes) }
                }
                .disabled(analysis.isDeleting)
            }
        } primaryAction: { ids in
            items.filter { ids.contains($0.id) }.forEach(analysis.revealInFinder)
        }
        .onKeyPress(.space) {
            guard selection.count == 1, let node = items.first(where: { selection.contains($0.id) }) else {
                return .ignored
            }
            analysis.quickLook(node)
            return .handled
        }
        .onDeleteCommand {
            items.filter { selection.contains($0.id) }.forEach(analysis.addToCleanup)
        }
        .focusedValue(\.trashSelection, selection.isEmpty ? nil : TrashSelection {
            let nodes = items.filter { selection.contains($0.id) }
            Task { await analysis.moveToTrash(nodes) }
        })
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("No Matching Files", systemImage: "magnifyingglass",
                                       description: Text("Nothing of this kind in \(analysis.focused.name)."))
            }
        }
    }

    /// The item's folder relative to the focused folder.
    private func location(of node: FileNode) -> String {
        let base = analysis.focused.path
        let folder = (node.path as NSString).deletingLastPathComponent
        guard folder.hasPrefix(base) else { return PathRules.friendlyPath(folder) }
        let relative = folder.dropFirst(base.count).drop { $0 == "/" }
        return relative.isEmpty ? analysis.focused.name : String(relative)
    }
}

private struct LargestItemRow: View {
    @Environment(\.theme) private var theme
    let node: FileNode
    let location: String
    let fraction: Double
    let isInCleanup: Bool
    let analysis: Analysis
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: node.icon)
                .resizable()
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Button("Quick Look", systemImage: "eye") { analysis.quickLook(node) }
                        Button("Reveal in Finder", systemImage: "magnifyingglass") { analysis.revealInFinder(node) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
                    Text(node.size.byteString)
                        .font(.callout.weight(.semibold).monospacedDigit())
                }
                HStack(spacing: 8) {
                    Label(location, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(theme.color.gradient)
                            .frame(width: max(3, proxy.size.width * fraction))
                    }
                    .frame(width: 120, height: 5)
                    .background(.quinary, in: Capsule())
                }
            }
            cleanupButton
        }
        .padding(.vertical, 5)
        .listRowSeparator(.hidden)
        .opacity(isInCleanup ? 0.45 : 1)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var cleanupButton: some View {
        if isInCleanup {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .help("In the cleanup list")
        } else {
            let canDelete = analysis.canDelete(node)
            Button("Add to Cleanup List", systemImage: "plus.circle") { analysis.addToCleanup(node) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(!canDelete)
                .help(canDelete ? "Add to the cleanup list (⌫)" : "Protected system folder")
        }
    }
}
