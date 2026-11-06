import DiskCleanerCore
import SwiftUI

/// Contents of the focused folder, largest first, color-matched to the size bar above.
struct ItemList: View {
    @Bindable var analysis: Analysis
    @FocusState private var isFocused: Bool

    var body: some View {
        let children = analysis.focusedChildren
        let total = max(analysis.focusedSize, 1)

        List(selection: $analysis.selection) {
            ForEach(Array(children.enumerated()), id: \.element.id) { index, node in
                ItemRow(
                    node: node,
                    size: node.size,
                    branch: index,
                    fraction: Double(node.size) / Double(total),
                    isHighlighted: analysis.highlighted === node,
                    isInCleanup: analysis.isInCleanup(node),
                    analysis: analysis
                )
                .tag(node.id)
                .onHover { inside in
                    if inside {
                        analysis.highlighted = node
                    } else if analysis.highlighted === node {
                        analysis.highlighted = nil
                    }
                }
                // Unlike `onDrag`, this leaves clicks to the List, so rows stay selectable
                // and double-click still reaches `primaryAction`.
                .itemProvider {
                    guard analysis.canDelete(node) else { return nil }
                    return NSItemProvider(object: URL(fileURLWithPath: node.path) as NSURL)
                }
            }
        }
        .contextMenu(forSelectionType: FileNode.ID.self) { ids in
            let nodes = ids.compactMap(analysis.node(withID:))
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
            guard ids.count == 1, let node = ids.first.flatMap(analysis.node(withID:)) else { return }
            activate(node)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // Clicking a row selects it without making the list key, which would leave
        // Return, Space and ⌫ unanswered.
        .focused($isFocused)
        .onChange(of: analysis.selection) {
            if !analysis.selection.isEmpty { isFocused = true }
        }
        .onKeyPress(.return) {
            guard let node = singleSelection else { return .ignored }
            activate(node)
            return .handled
        }
        .onKeyPress(.space) {
            guard let node = singleSelection else { return .ignored }
            analysis.quickLook(node)
            return .handled
        }
        // The list handles the Delete key itself, so ⌫ arrives as the Delete command and
        // ⌘⌫ through the Move to Trash menu item.
        .onDeleteCommand {
            analysis.selection.compactMap(analysis.node(withID:)).forEach(analysis.addToCleanup)
        }
        .focusedValue(\.trashSelection, selectedNodes.isEmpty ? nil : TrashSelection {
            Task { await analysis.moveToTrash(selectedNodes) }
        })
        .overlay {
            if children.isEmpty {
                ContentUnavailableView(
                    analysis.focused.isUnreadable ? "Not Readable" : "Empty Folder",
                    systemImage: analysis.focused.isUnreadable ? "lock" : "folder",
                    description: Text(analysis.focused.isUnreadable
                        ? "Grant Full Disk Access to measure this folder."
                        : "Nothing takes up space here.")
                )
            }
        }
    }

    private var selectedNodes: [FileNode] {
        analysis.selection.compactMap(analysis.node(withID:))
    }

    private var singleSelection: FileNode? {
        guard analysis.selection.count == 1 else { return nil }
        return analysis.selection.first.flatMap(analysis.node(withID:))
    }

    /// Double-click or Return: folders zoom in, files open in their default app.
    private func activate(_ node: FileNode) {
        if node.isDirectory {
            withAnimation(.easeOut(duration: 0.45)) { analysis.focus(node) }
        } else {
            analysis.open(node)
        }
    }
}

private struct ItemRow: View {
    @Environment(\.theme) private var theme
    let node: FileNode
    /// Passed separately because `FileNode` changes are invisible to SwiftUI's diffing.
    let size: Int64
    /// Position in the folder, which picks the row's color.
    let branch: Int
    let fraction: Double
    let isHighlighted: Bool
    let isInCleanup: Bool
    let analysis: Analysis

    private var color: Color {
        theme.palette.color(branch: branch, shade: 0, isDirectory: node.isDirectory)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: node.icon)
                .resizable()
                .frame(width: 30, height: 30)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if node.isUnreadable {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Not measured — grant Full Disk Access")
                    }
                    Spacer(minLength: 8)
                    hoverActions
                        .opacity(isHighlighted ? 1 : 0)
                        .allowsHitTesting(isHighlighted)
                    Text(size.byteString)
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text(fraction.formatted(.percent.precision(.fractionLength(1))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 48, alignment: .trailing)
                }
                bar
            }
            cleanupButton
            zoomButton
        }
        .padding(.vertical, 6)
        .listRowSeparator(.hidden)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted ? theme.color.opacity(0.1) : .clear)
                .padding(.horizontal, 6)
        )
        .opacity(isInCleanup ? 0.45 : 1)
    }

    /// Folders show what is inside them as shades of the row's color.
    @ViewBuilder
    private var bar: some View {
        let parts = node.isDirectory ? Breakdown(of: node, maxParts: 6).parts : []
        if parts.isEmpty {
            SizeBar(parts: [], height: 8, color: { _ in color })
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(color.gradient)
                            .frame(width: max(3, proxy.size.width * fraction))
                    }
                }
        } else {
            SizeBar(parts: parts, filled: fraction, height: 8, spacing: 1,
                    color: { [palette = theme.palette] in palette.color(for: $0, insideBranch: branch) })
        }
    }

    private var hoverActions: some View {
        HStack(spacing: 6) {
            Button("Quick Look", systemImage: "eye") { analysis.quickLook(node) }
                .help("Quick Look (Space)")
            if node.isDirectory {
                Button("Open in Finder", systemImage: "folder") { analysis.showInFinder(node) }
                    .help("Open in Finder")
            } else {
                Button("Reveal in Finder", systemImage: "magnifyingglass") { analysis.showInFinder(node) }
                    .help("Reveal in Finder")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var zoomButton: some View {
        if node.isDirectory {
            Button("Open Folder", systemImage: "chevron.right") {
                withAnimation(.easeOut(duration: 0.45)) { analysis.focus(node) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Show what's inside (double-click or Return)")
            .frame(width: 14)
        } else {
            Color.clear.frame(width: 14, height: 1)
        }
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
