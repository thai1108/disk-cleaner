@testable import DiskCleanerCore

/// Builds an in-memory tree without touching the file system.
enum TreeFixtures {
    struct Spec {
        let name: String
        let size: Int64
        let children: [Spec]?

        static func file(_ name: String, _ size: Int64) -> Spec { Spec(name: name, size: size, children: nil) }
        static func dir(_ name: String, _ children: [Spec]) -> Spec { Spec(name: name, size: 0, children: children) }
    }

    static func tree(_ path: String, _ children: [Spec]) -> FileNode {
        let root = FileNode(rootPath: path, kind: .directory)
        root.children = children.map { build($0, parent: root) }
        root.finalizeSubtree()
        return root
    }

    private static func build(_ spec: Spec, parent: FileNode) -> FileNode {
        guard let children = spec.children else {
            return FileNode(name: spec.name, kind: .file, size: spec.size, parent: parent)
        }
        let node = FileNode(name: spec.name, kind: .directory, parent: parent)
        node.children = children.map { build($0, parent: node) }
        return node
    }
}
