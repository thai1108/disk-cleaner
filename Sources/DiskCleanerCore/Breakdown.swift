/// A folder's largest items as parts of a stacked bar. Items too small to see are merged
/// into one trailing "other items" part.
public struct Breakdown: Sendable {
    public enum Content: Sendable {
        case node(FileNode)
        case otherItems(count: Int)
    }

    public struct Part: Identifiable, Sendable {
        /// Position in the bar, largest first.
        public let id: Int
        public let content: Content
        public let size: Int64
        /// Share of the folder's size, 0...1.
        public let fraction: Double

        public var node: FileNode? {
            if case .node(let node) = content { return node }
            return nil
        }
    }

    public let parts: [Part]

    /// - Parameters:
    ///   - maxParts: Most items shown on their own, not counting the merged part.
    ///   - minimumFraction: Items smaller than this share of the folder are merged.
    public init(of folder: FileNode, maxParts: Int = 8, minimumFraction: Double = 0.01) {
        let total = Double(folder.size)
        guard total > 0 else {
            parts = []
            return
        }
        var parts: [Part] = []
        var children = folder.children[...]
        while let child = children.first, parts.count < maxParts, Double(child.size) / total >= minimumFraction {
            parts.append(Part(id: parts.count, content: .node(child), size: child.size, fraction: Double(child.size) / total))
            children = children.dropFirst()
        }
        let otherSize = children.reduce(0) { $0 + $1.size }
        if otherSize > 0 {
            parts.append(Part(id: parts.count, content: .otherItems(count: children.count), size: otherSize,
                              fraction: Double(otherSize) / total))
        }
        self.parts = parts
    }
}
