/// Items queued for deletion. Never holds both an item and one of its descendants,
/// so the total size never counts the same bytes twice.
public struct CleanupList: Sendable {
    public private(set) var items: [FileNode] = []

    public init() {}

    public var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    public var isEmpty: Bool { items.isEmpty }

    public func contains(_ node: FileNode) -> Bool {
        items.contains { $0 === node || node.isDescendant(of: $0) }
    }

    /// Adds `node` unless it is already covered by a queued ancestor; drops queued descendants.
    public mutating func add(_ node: FileNode) {
        guard node.parent != nil, !contains(node) else { return }
        items.removeAll { $0.isDescendant(of: node) }
        items.append(node)
    }

    /// Removes `node` and any queued descendants, e.g. once `node` has been deleted.
    public mutating func remove(_ node: FileNode) {
        items.removeAll { $0 === node || $0.isDescendant(of: node) }
    }

    public mutating func removeAll() {
        items.removeAll()
    }
}
