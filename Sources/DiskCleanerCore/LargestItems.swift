import Foundation

/// Kinds of files that are often big and often forgotten.
public enum FileKind: String, CaseIterable, Sendable {
    case video, archive, diskImage, installer, application

    private static let extensions: [FileKind: Set<String>] = [
        .video: ["mp4", "mov", "m4v", "mkv", "avi", "wmv", "flv", "webm", "mpg", "mpeg", "3gp"],
        .archive: ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"],
        .diskImage: ["dmg", "iso", "img", "sparseimage", "vmdk", "vdi", "qcow2"],
        .installer: ["pkg", "mpkg", "xip", "ipa", "apk"],
        .application: ["app"],
    ]

    public init?(fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let kind = Self.extensions.first(where: { $0.value.contains(ext) })?.key else { return nil }
        self = kind
    }
}

extension FileNode {
    /// Folders Finder shows as a single item, such as apps and photo libraries.
    public var isPackage: Bool {
        guard isDirectory else { return false }
        return Self.packageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static let packageExtensions: Set<String> = [
        "app", "photoslibrary", "musiclibrary", "tvlibrary", "xcarchive", "sparsebundle", "bundle", "framework",
    ]

    /// The `limit` largest files and packages in this subtree, largest first, optionally
    /// only of one kind. Packages count as one item; their contents are not listed.
    public func largestItems(limit: Int, kind: FileKind? = nil) -> [FileNode] {
        guard limit > 0 else { return [] }
        var result: [FileNode] = []
        var stack = children
        while let node = stack.popLast() {
            if node.isDirectory, !node.isPackage {
                stack.append(contentsOf: node.children)
                continue
            }
            guard result.count < limit || node.size > result[result.count - 1].size else { continue }
            if let kind, FileKind(fileName: node.name) != kind { continue }
            let index = result.firstIndex { $0.size < node.size } ?? result.count
            result.insert(node, at: index)
            if result.count > limit { result.removeLast() }
        }
        return result
    }
}
