import DiskCleanerCore
import SwiftUI

/// Floating drop zone holding items picked for deletion, with the delete action.
struct CleanupBar: View {
    @Environment(\.theme) private var theme
    @Bindable var analysis: Analysis
    @State private var isDropTargeted = false
    @State private var isConfirming = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.full")
                .font(.title3)
                .foregroundStyle(isDropTargeted ? theme.color : .secondary)
                .frame(width: 24)

            if analysis.cleanupList.isEmpty {
                Text("Drop items here, or press ⌫ or +, to add them to the cleanup list")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(analysis.cleanupList.items) { node in
                            CleanupChip(node: node, analysis: analysis)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Clear") { analysis.clearCleanup() }
                    .buttonStyle(.borderless)
                    .disabled(analysis.isDeleting)
            }

            Button(role: .destructive) {
                isConfirming = true
            } label: {
                if analysis.isDeleting {
                    ProgressView().controlSize(.small)
                } else if analysis.cleanupList.isEmpty {
                    Label("Delete", systemImage: "trash")
                } else {
                    Label("Delete \(analysis.cleanupList.totalSize.byteString)", systemImage: "trash")
                }
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(analysis.cleanupList.isEmpty || analysis.isDeleting)
        }
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassEffect(isDropTargeted ? .regular.tint(theme.color.opacity(0.25)) : .regular, in: .capsule)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .dropDestination(for: URL.self) { urls, _ in
            let nodes = urls.compactMap(analysis.node(for:))
            nodes.forEach(analysis.addToCleanup)
            return !nodes.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .confirmationDialog(
            "Delete \(analysis.cleanupList.items.count) item(s) (\(analysis.cleanupList.totalSize.byteString))?",
            isPresented: $isConfirming
        ) {
            Button("Move to Trash") {
                Task { await analysis.deleteCleanupItems(permanently: false) }
            }
            Button("Delete Immediately", role: .destructive) {
                Task { await analysis.deleteCleanupItems(permanently: true) }
            }
        } message: {
            Text("Moving to the Trash frees the space once you empty it. Deleting immediately cannot be undone.")
        }
    }
}

private struct CleanupChip: View {
    let node: FileNode
    let analysis: Analysis

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: node.icon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(node.name)
                .lineLimit(1)
                .frame(maxWidth: 160)
            Text(node.size.byteString)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                analysis.removeFromCleanup(node)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove from the cleanup list")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quinary, in: Capsule())
        .help(PathRules.friendlyPath(node.path))
        .contextMenu { NodeMenu(node: node, analysis: analysis) }
    }
}

/// Confirms the last cleanup, with Undo and Empty Trash for items moved to the Trash.
struct CleanupToast: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let report: CleanupReport
    let analysis: Analysis

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: report.movedToTrash ? "trash.circle.fill" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(theme.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if report.movedToTrash {
                    Text("The space is freed once you empty the Trash.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if report.movedToTrash {
                Button("Undo") { Task { await analysis.undoLastCleanup() } }
                    .disabled(analysis.isDeleting)
                Button("Empty Trash…") { model.requestEmptyTrash() }
            }
            Button("Dismiss", systemImage: "xmark") { analysis.dismissCleanupReport() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .buttonStyle(.glass)
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 680)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 20)
        // Leaves time to undo; a plain delete only needs a quick confirmation.
        .task(id: report.id) {
            try? await Task.sleep(for: .seconds(report.movedToTrash ? 20 : 8))
            if analysis.lastCleanup?.id == report.id { analysis.dismissCleanupReport() }
        }
    }

    private var title: String {
        let items = report.itemCount == 1 ? "1 item" : "\(report.itemCount.formatted()) items"
        return report.movedToTrash
            ? "Moved \(items) (\(report.bytes.byteString)) to the Trash"
            : "Deleted \(items) and freed \(report.bytes.byteString)"
    }
}
