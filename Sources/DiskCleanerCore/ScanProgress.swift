import Synchronization

/// Live counters a UI can poll while a scan runs on background threads.
public final class ScanProgress: Sendable {
    private let files = Atomic<Int>(0)
    private let directories = Atomic<Int>(0)
    private let bytes = Atomic<Int64>(0)
    private let unreadable = Atomic<Int>(0)
    private let lastPath = Mutex<String>("")

    public init() {}

    public var filesScanned: Int { files.load(ordering: .relaxed) }
    public var directoriesScanned: Int { directories.load(ordering: .relaxed) }
    public var bytesScanned: Int64 { bytes.load(ordering: .relaxed) }
    public var unreadableDirectories: Int { unreadable.load(ordering: .relaxed) }
    public var currentPath: String { lastPath.withLock { $0 } }

    func recordDirectory(path: String, files fileCount: Int, bytes byteCount: Int64) {
        directories.add(1, ordering: .relaxed)
        files.add(fileCount, ordering: .relaxed)
        bytes.add(byteCount, ordering: .relaxed)
        lastPath.withLock { $0 = path }
    }

    func recordUnreadable() {
        unreadable.add(1, ordering: .relaxed)
    }
}
