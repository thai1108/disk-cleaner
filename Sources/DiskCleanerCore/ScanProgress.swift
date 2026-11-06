import os

/// Live counters a UI can poll while a scan runs on background threads.
public final class ScanProgress: Sendable {
    private struct Counts {
        var files = 0
        var directories = 0
        var bytes: Int64 = 0
        var unreadable = 0
        var lastPath = ""
    }

    // One lock per finished directory is cheap next to listing it.
    private let counts = OSAllocatedUnfairLock(initialState: Counts())

    public init() {}

    public var filesScanned: Int { counts.withLock { $0.files } }
    public var directoriesScanned: Int { counts.withLock { $0.directories } }
    public var bytesScanned: Int64 { counts.withLock { $0.bytes } }
    public var unreadableDirectories: Int { counts.withLock { $0.unreadable } }
    public var currentPath: String { counts.withLock { $0.lastPath } }

    func recordDirectory(path: String, files fileCount: Int, bytes byteCount: Int64) {
        counts.withLock {
            $0.directories += 1
            $0.files += fileCount
            $0.bytes += byteCount
            $0.lastPath = path
        }
    }

    func recordUnreadable() {
        counts.withLock { $0.unreadable += 1 }
    }
}
