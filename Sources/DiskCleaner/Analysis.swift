import AppKit
import DiskCleanerCore
import Observation

/// The latest cleanup, for the confirmation toast and for Undo.
struct CleanupReport: Identifiable {
    struct TrashedItem {
        let node: FileNode
        let parent: FileNode
        let original: URL
        let inTrash: URL
    }

    let id = UUID()
    let itemCount: Int
    let bytes: Int64
    /// Empty when the items were deleted immediately.
    let trashed: [TrashedItem]

    var movedToTrash: Bool { !trashed.isEmpty }
}

/// State of one finished scan: navigation, highlighting, the cleanup list, and deletion.
@MainActor @Observable
final class Analysis {
    let target: ScanTarget
    let root: FileNode
    let unreadableCount: Int
    let duration: TimeInterval
    let scannedAt = Date()

    private(set) var focused: FileNode
    private(set) var cleanupList = CleanupList()
    /// Bumped whenever the tree changes, since `FileNode` itself is not observable.
    private(set) var revision = 0

    enum ListMode: Hashable {
        case contents, largest
    }

    var listMode = ListMode.contents
    /// Narrows the largest-files list to one kind of file; nil shows everything.
    var largestKind: FileKind?
    @ObservationIgnored private var largestCache: (key: LargestKey, items: [FileNode])?

    private struct LargestKey: Equatable {
        let folder: ObjectIdentifier
        let kind: FileKind?
        let revision: Int
    }

    var selection: Set<FileNode.ID> = []
    /// Item under the pointer, in either the size bar or the list.
    var highlighted: FileNode?
    var quickLookURL: URL?
    var isDeleting = false
    var deletionFailures: [String] = []
    private(set) var lastCleanup: CleanupReport?
    /// The scanned volume as it is now; refreshed after every cleanup.
    private(set) var volume: Volume?
    /// Bytes this scan moved to the Trash: still used on the volume, but gone from the tree.
    private(set) var trashedBytes: Int64 = 0
    /// Lets the rest of the app refresh free space after files are removed or restored.
    var onSpaceChanged: (() -> Void)?

    init(target: ScanTarget, root: FileNode, unreadableCount: Int, duration: TimeInterval) {
        self.target = target
        self.root = root
        self.unreadableCount = unreadableCount
        self.duration = duration
        focused = root
        volume = target.volume
    }

    // Tree-derived values are read through `revision` so views refresh after deletions.

    var focusedChildren: [FileNode] {
        _ = revision
        return focused.children
    }

    var focusedSize: Int64 {
        _ = revision
        return focused.size
    }

    var focusedSummary: String {
        _ = revision
        return focused.itemSummary
    }

    var totalSize: Int64 {
        _ = revision
        return root.size
    }

    var totalFileCount: Int {
        _ = revision
        return root.fileCount
    }

    /// The focused folder's largest items, for its size bar.
    var focusedBreakdown: Breakdown {
        _ = revision
        return Breakdown(of: focused)
    }

    /// The largest files and packages under the focused folder, cached until the folder,
    /// the filter, or the tree changes.
    var largestItems: [FileNode] {
        let key = LargestKey(folder: ObjectIdentifier(focused), kind: largestKind, revision: revision)
        if let largestCache, largestCache.key == key { return largestCache.items }
        let items = focused.largestItems(limit: 200, kind: largestKind)
        largestCache = (key, items)
        return items
    }

    /// Path from the scan root down to the focused folder.
    var breadcrumb: [FileNode] {
        _ = revision
        return focused.ancestors + [focused]
    }

    /// Space used on the volume that the scan could not see: the sealed system volume,
    /// APFS snapshots, other users' files, and anything unreadable.
    var unaccountedSpace: Int64? {
        guard let volume else { return nil }
        return max(0, volume.usedCapacity - totalSize - trashedBytes)
    }

    func focus(_ node: FileNode) {
        guard node.isDirectory, node !== focused else { return }
        focused = node
        selection = []
        highlighted = nil
    }

    func focusParent() {
        if let parent = focused.parent { focus(parent) }
    }

    func node(withID id: FileNode.ID) -> FileNode? {
        focused.children.first { $0.id == id }
    }

    /// Resolves a dropped file URL (from this app or Finder) to a node in the tree.
    func node(for url: URL) -> FileNode? {
        root.descendant(at: url)
    }

    // MARK: Cleanup list

    func canDelete(_ node: FileNode) -> Bool {
        node !== root && !PathRules.isProtected(node.path)
    }

    func isInCleanup(_ node: FileNode) -> Bool {
        _ = revision
        return cleanupList.contains(node)
    }

    func addToCleanup(_ node: FileNode) {
        guard canDelete(node) else { return }
        cleanupList.add(node)
    }

    func removeFromCleanup(_ node: FileNode) {
        cleanupList.remove(node)
    }

    func clearCleanup() {
        cleanupList.removeAll()
    }

    /// Moves everything in the cleanup list to the Trash (or deletes it), then updates the tree.
    func deleteCleanupItems(permanently: Bool) async {
        await delete(cleanupList.items, permanently: permanently)
    }

    /// Finder-style ⌘⌫: trashes the items right away, bypassing the cleanup list.
    func moveToTrash(_ nodes: [FileNode]) async {
        // Reuses the cleanup list rules so an item and its descendant are never both trashed.
        var picked = CleanupList()
        nodes.filter(canDelete).forEach { picked.add($0) }
        await delete(picked.items, permanently: false)
    }

    private func delete(_ items: [FileNode], permanently: Bool) async {
        guard !items.isEmpty, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let urls = items.map { URL(fileURLWithPath: PathRules.friendlyPath($0.path)) }
        let outcomes = await Task.detached(priority: .userInitiated) {
            Self.remove(urls, permanently: permanently)
        }.value

        var failures: [String] = []
        var trashed: [CleanupReport.TrashedItem] = []
        var removedCount = 0
        var removedBytes: Int64 = 0
        for (index, node) in items.enumerated() {
            switch outcomes[index] {
            case .failure(let error):
                failures.append("\(node.name): \(error.localizedDescription)")
            case .success(let inTrash):
                guard let parent = node.parent else { continue }
                if focused === node || focused.isDescendant(of: node) {
                    focused = parent
                }
                cleanupList.remove(node)
                node.removeFromParent()
                removedCount += 1
                removedBytes += node.size
                if let inTrash {
                    trashed.append(.init(node: node, parent: parent, original: urls[index], inTrash: inTrash))
                }
            }
        }
        trashedBytes += trashed.reduce(0) { $0 + $1.node.size }
        lastCleanup = removedCount > 0
            ? CleanupReport(itemCount: removedCount, bytes: removedBytes, trashed: trashed)
            : nil
        deletionFailures = failures
        selection = []
        highlighted = nil
        revision += 1
        spaceChanged()
    }

    /// Moves the last cleanup's items back from the Trash.
    func undoLastCleanup() async {
        guard let report = lastCleanup, report.movedToTrash, !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let moves = report.trashed.map { (from: $0.inTrash, to: $0.original) }
        let outcomes = await Task.detached(priority: .userInitiated) {
            moves.map { move in
                Result { try FileManager.default.moveItem(at: move.from, to: move.to) }
            }
        }.value

        var failures: [String] = []
        for (item, outcome) in zip(report.trashed, outcomes) {
            switch outcome {
            case .success:
                item.node.reattach(to: item.parent)
                trashedBytes -= item.node.size
            case .failure(let error):
                failures.append("\(item.node.name): \(error.localizedDescription)")
            }
        }
        lastCleanup = nil
        deletionFailures = failures
        revision += 1
        spaceChanged()
    }

    func dismissCleanupReport() {
        lastCleanup = nil
    }

    /// The Trash was emptied: what this scan put there is gone for good.
    func trashWasEmptied() {
        trashedBytes = 0
        if lastCleanup?.movedToTrash == true { lastCleanup = nil }
        spaceChanged()
    }

    private func spaceChanged() {
        if let current = volume {
            volume = Volume.mounted().first { $0.url == current.url } ?? current
        }
        onSpaceChanged?()
    }

    /// For each URL, where it went in the Trash (nil when deleted immediately) or the error.
    private nonisolated static func remove(_ urls: [URL], permanently: Bool) -> [Result<URL?, Error>] {
        urls.map { url in
            Result {
                if permanently {
                    try FileManager.default.removeItem(at: url)
                    return nil
                }
                var inTrash: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &inTrash)
                return inTrash as URL?
            }
        }
    }

    // MARK: Finder

    func revealInFinder(_ node: FileNode) {
        NSWorkspace.shared.activateFileViewerSelecting([displayURL(node)])
    }

    /// Opens a folder's contents in a Finder window, or reveals a file in its folder.
    /// Unlike `open`, this never launches an app bundle.
    func showInFinder(_ node: FileNode) {
        if node.isDirectory {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: displayURL(node).path)
        } else {
            revealInFinder(node)
        }
    }

    func open(_ node: FileNode) {
        NSWorkspace.shared.open(displayURL(node))
    }

    func quickLook(_ node: FileNode) {
        quickLookURL = displayURL(node)
    }

    func copyPath(_ node: FileNode) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PathRules.friendlyPath(node.path), forType: .string)
    }

    func displayURL(_ node: FileNode) -> URL {
        URL(fileURLWithPath: PathRules.friendlyPath(node.path), isDirectory: node.isDirectory)
    }
}
