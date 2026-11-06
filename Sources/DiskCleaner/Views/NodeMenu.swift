import DiskCleanerCore
import SwiftUI

/// Context-menu actions shared by the list, the size bar, the breadcrumb, and the cleanup list.
struct NodeMenu: View {
    let node: FileNode
    let analysis: Analysis

    var body: some View {
        if node.isDirectory {
            if node !== analysis.focused {
                Button("Show Contents", systemImage: "arrow.right.circle") {
                    withAnimation(.easeOut(duration: 0.45)) { analysis.focus(node) }
                }
            }
            Button("Open in Finder", systemImage: "folder") { analysis.showInFinder(node) }
        } else {
            Button("Open", systemImage: "arrow.up.forward.app") { analysis.open(node) }
        }
        Button("Reveal in Finder", systemImage: "magnifyingglass") { analysis.revealInFinder(node) }
        Button("Quick Look", systemImage: "eye") { analysis.quickLook(node) }
        Button("Copy Path", systemImage: "doc.on.doc") { analysis.copyPath(node) }
        Divider()
        if analysis.isInCleanup(node) {
            Button("Remove from Cleanup List", systemImage: "minus.circle") { analysis.removeFromCleanup(node) }
        } else {
            Button("Add to Cleanup List", systemImage: "tray.and.arrow.down") { analysis.addToCleanup(node) }
                .disabled(!analysis.canDelete(node))
        }
        Button("Move to Trash", systemImage: "trash") {
            Task { await analysis.moveToTrash([node]) }
        }
        .disabled(!analysis.canDelete(node) || analysis.isDeleting)
    }
}

/// Moves the focused list's selected items to the Trash; drives File › Move to Trash (⌘⌫).
struct TrashSelection {
    let perform: () -> Void
}

extension FocusedValues {
    @Entry var trashSelection: TrashSelection?
}

struct TrashCommands: Commands {
    @FocusedValue(\.trashSelection) private var trashSelection

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Move to Trash") { trashSelection?.perform() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(trashSelection == nil)
        }
    }
}
