import Foundation

/// A file or directory in a scanned tree. Sizes are on-disk (allocated) bytes.
///
/// Nodes are mutated by the scanner while it builds the tree (each directory node is
/// written by exactly one worker), and afterwards only from the main actor.
public final class FileNode: Identifiable, @unchecked Sendable {
    public enum Kind: UInt8, Sendable {
        case file, directory, symlink, other
    }

    public let name: String
    public let kind: Kind
    public internal(set) var size: Int64
    /// Number of non-directory items in this subtree (1 for a file).
    public internal(set) var fileCount: Int
    /// Sorted by size, largest first, once the scan has finished.
    public internal(set) var children: [FileNode] = []
    public internal(set) weak var parent: FileNode?
    /// The directory could not be read (usually a privacy/permission restriction).
    public internal(set) var isUnreadable = false

    /// Absolute path; only stored on the root, other nodes derive it from their ancestors.
    private let rootPath: String?

    public var id: ObjectIdentifier { ObjectIdentifier(self) }
    public var isDirectory: Bool { kind == .directory }

    init(name: String, kind: Kind, size: Int64 = 0, parent: FileNode?) {
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = kind == .directory ? 0 : 1
        self.parent = parent
        self.rootPath = nil
    }

    init(rootPath: String, kind: Kind, size: Int64 = 0) {
        let lastComponent = (rootPath as NSString).lastPathComponent
        self.name = lastComponent.isEmpty ? rootPath : lastComponent
        self.kind = kind
        self.size = size
        self.fileCount = kind == .directory ? 0 : 1
        self.parent = nil
        self.rootPath = rootPath
    }

    public var path: String {
        guard let parent else { return rootPath ?? name }
        let parentPath = parent.path
        return parentPath.hasSuffix("/") ? parentPath + name : parentPath + "/" + name
    }

    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: isDirectory)
    }

    /// Ancestors from the root down to (but excluding) this node.
    public var ancestors: [FileNode] {
        var result: [FileNode] = []
        var current = parent
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result.reversed()
    }

    public func isDescendant(of other: FileNode) -> Bool {
        var current = parent
        while let node = current {
            if node === other { return true }
            current = node.parent
        }
        return false
    }

    /// Finds a node by absolute path inside this subtree.
    public func descendant(atPath target: String) -> FileNode? {
        let base = path
        if target == base { return self }
        let prefix = base.hasSuffix("/") ? base : base + "/"
        guard target.hasPrefix(prefix) else { return nil }

        var node = self
        for component in target.dropFirst(prefix.count).split(separator: "/") {
            guard let next = node.children.first(where: { $0.name == component }) else { return nil }
            node = next
        }
        return node
    }

    /// Finds the node for a file URL from Finder or a drag, which may spell the path
    /// differently from the scan: `/Users/…` for the Data volume, or `/tmp` for `/private/tmp`.
    /// The URL is deliberately not standardized, since that strips `/private` and breaks
    /// lookups in trees scanned at `/private/…`.
    public func descendant(at url: URL) -> FileNode? {
        let target = url.path
        if let node = descendant(atPath: target) ?? descendant(atPath: PathRules.dataVolumePath(for: target)) {
            return node
        }
        guard let realTarget = Self.realPath(target), let realBase = Self.realPath(path) else { return nil }
        if realTarget == realBase { return self }
        guard realTarget.hasPrefix(realBase + "/") else { return nil }
        return descendant(atPath: path + realTarget.dropFirst(realBase.count))
    }

    private static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Detaches this node from the tree and subtracts its size from every ancestor.
    public func removeFromParent() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }

        var current: FileNode? = parent
        while let node = current {
            node.size -= size
            node.fileCount -= fileCount
            // The ancestor shrank, so its position among its siblings may have changed.
            node.parent?.children.sort(by: FileNode.largerFirst)
            current = node.parent
        }
        self.parent = nil
    }

    /// Puts a node detached with `removeFromParent()` back, e.g. when a delete is undone.
    public func reattach(to parent: FileNode) {
        guard self.parent == nil else { return }
        self.parent = parent
        parent.children.append(self)
        parent.children.sort(by: FileNode.largerFirst)

        var current: FileNode? = parent
        while let node = current {
            node.size += size
            node.fileCount += fileCount
            node.parent?.children.sort(by: FileNode.largerFirst)
            current = node.parent
        }
    }

    /// Rolls child sizes up into directories and sorts every child list, largest first.
    /// Iterative so arbitrarily deep trees cannot overflow the stack.
    func finalizeSubtree() {
        var stack: [(node: FileNode, childrenVisited: Bool)] = [(self, false)]
        while let (node, childrenVisited) = stack.popLast() {
            guard node.isDirectory else { continue }
            if childrenVisited {
                var size: Int64 = 0
                var fileCount = 0
                for child in node.children {
                    size += child.size
                    fileCount += child.fileCount
                }
                node.size = size
                node.fileCount = fileCount
                node.children.sort(by: FileNode.largerFirst)
            } else {
                stack.append((node, true))
                for child in node.children where child.isDirectory {
                    stack.append((child, false))
                }
            }
        }
    }

    static func largerFirst(_ lhs: FileNode, _ rhs: FileNode) -> Bool {
        lhs.size != rhs.size ? lhs.size > rhs.size : lhs.name < rhs.name
    }
}
