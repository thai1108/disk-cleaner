import Foundation

/// The user's Trash (`~/.Trash`). macOS only lets apps with Full Disk Access read it.
public enum TrashFolder {
    public struct Summary: Sendable, Equatable {
        public let itemCount: Int
        public let size: Int64
    }

    public static func path(home: String = NSHomeDirectory()) -> String {
        home + "/.Trash"
    }

    /// Throws when the Trash cannot be read, usually for lack of Full Disk Access.
    public static func measure(home: String = NSHomeDirectory()) throws -> Summary {
        let root = try DiskScanner.scanBlocking(path: path(home: home))
        if root.isUnreadable { throw ScanError.unreadable(root.path, errno: EPERM) }
        let items = root.children.filter { $0.name != ".DS_Store" }
        return Summary(itemCount: items.count, size: root.size)
    }

    /// Permanently removes everything in the Trash. Returns what could not be removed.
    public static func empty(home: String = NSHomeDirectory()) -> [String] {
        let trash = path(home: home)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: trash) else { return [trash] }
        var failures: [String] = []
        for name in names {
            do {
                try FileManager.default.removeItem(atPath: trash + "/" + name)
            } catch {
                failures.append("\(name): \(error.localizedDescription)")
            }
        }
        return failures
    }
}
