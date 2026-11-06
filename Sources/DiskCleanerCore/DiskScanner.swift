import Darwin
import Foundation
import os

public struct ScanOptions: Sendable {
    /// Descend into directories that are mount points of other volumes.
    public var crossesMountPoints = false
    /// Directories to list but not enter, marked unreadable instead, e.g. folders where
    /// macOS would stop the scan to ask the user for permission. Gets the full path.
    public var skipsDirectory: (@Sendable (String) -> Bool)?
    public var workerCount = max(4, ProcessInfo.processInfo.activeProcessorCount)

    public init() {}
}

public enum ScanError: LocalizedError, Equatable {
    case notFound(String)
    case unreadable(String, errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .notFound(let path):
            "“\(path)” does not exist."
        case .unreadable(let path, let code):
            "Cannot read “\(path)”: \(String(cString: strerror(code)))."
        }
    }
}

/// Builds a `FileNode` tree using `getattrlistbulk(2)`, reading many directories in parallel.
public enum DiskScanner {
    public static func scan(
        path: String,
        options: ScanOptions = ScanOptions(),
        progress: ScanProgress = ScanProgress()
    ) async throws -> FileNode {
        let cancellation = Flag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let thread = Thread {
                    continuation.resume(with: Result {
                        try scanBlocking(path: path, options: options, progress: progress) {
                            cancellation.isSet
                        }
                    })
                }
                thread.stackSize = 8 << 20
                thread.qualityOfService = .userInitiated
                thread.start()
            }
        } onCancel: {
            cancellation.set()
        }
    }

    /// Synchronous scan; blocks the calling thread until the whole tree is built.
    public static func scanBlocking(
        path: String,
        options: ScanOptions = ScanOptions(),
        progress: ScanProgress = ScanProgress(),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> FileNode {
        var info = stat()
        guard lstat(path, &info) == 0 else {
            throw errno == ENOENT ? ScanError.notFound(path) : ScanError.unreadable(path, errno: errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            let kind: FileNode.Kind = (info.st_mode & S_IFMT) == S_IFLNK ? .symlink : .file
            return FileNode(rootPath: path, kind: kind, size: Int64(info.st_blocks) * 512)
        }

        let root = FileNode(rootPath: path, kind: .directory)
        let pool = WorkStack([DirectoryJob(node: root, path: path)])
        let hardLinks = HardLinkRegistry()
        let canceled = Flag()

        WorkStack<DirectoryJob>.runWorkers(count: options.workerCount) { _ in
            var reader = DirectoryReader(options: options)
            defer { reader.deallocate() }
            while let job = pool.next() {
                if isCancelled() {
                    canceled.set()
                    pool.stop()
                    break
                }
                let subdirectories = reader.read(job, progress: progress, hardLinks: hardLinks)
                pool.complete(spawning: subdirectories)
            }
        }

        if canceled.isSet { throw CancellationError() }
        root.finalizeSubtree()
        return root
    }
}

struct DirectoryJob: Sendable {
    let node: FileNode
    let path: String
}

private final class Flag: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: false)
    var isSet: Bool { value.withLock { $0 } }
    func set() { value.withLock { $0 = true } }
}

/// File IDs of hard-linked files already counted, so each inode's space is counted once.
private final class HardLinkRegistry: Sendable {
    private let seen = OSAllocatedUnfairLock(initialState: Set<UInt64>())

    func isFirstLink(_ fileID: UInt64) -> Bool {
        seen.withLock { $0.insert(fileID).inserted }
    }
}

/// Per-worker state for listing directories with `getattrlistbulk`.
private struct DirectoryReader {
    private static let bufferSize = 256 * 1024

    private let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 16)
    private var request = attrlist()
    private let crossesMountPoints: Bool
    private let skipsDirectory: (@Sendable (String) -> Bool)?

    init(options: ScanOptions) {
        crossesMountPoints = options.crossesMountPoints
        skipsDirectory = options.skipsDirectory
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = Attr.returned | Attr.error | Attr.name | Attr.objectType | Attr.fileID
        request.dirattr = Attr.mountStatus
        request.fileattr = Attr.linkCount | Attr.allocatedSize
    }

    func deallocate() {
        buffer.deallocate()
    }

    /// Lists one directory, attaches its children to `job.node`, and returns jobs for subdirectories.
    mutating func read(_ job: DirectoryJob, progress: ScanProgress, hardLinks: HardLinkRegistry) -> [DirectoryJob] {
        let descriptor = open(job.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            job.node.isUnreadable = true
            progress.recordUnreadable()
            return []
        }
        defer { close(descriptor) }

        var children: [FileNode] = []
        var subdirectories: [DirectoryJob] = []
        var fileCount = 0
        var byteCount: Int64 = 0
        let basePath = job.path.hasSuffix("/") ? job.path : job.path + "/"

        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, Self.bufferSize, 0)
            if count < 0 {
                job.node.isUnreadable = true
                progress.recordUnreadable()
                break
            }
            if count == 0 { break }

            var entry = UnsafeRawPointer(buffer)
            for _ in 0..<count {
                let length = Int(entry.loadUnaligned(as: UInt32.self))
                defer { entry += length }
                guard let parsed = Entry(at: entry) else { continue }

                switch parsed.kind {
                case .directory:
                    if parsed.isMountPoint, !crossesMountPoints { continue }
                    let child = FileNode(name: parsed.name, kind: .directory, parent: job.node)
                    children.append(child)
                    let path = basePath + parsed.name
                    if skipsDirectory?(path) == true {
                        child.isUnreadable = true
                        progress.recordUnreadable()
                    } else {
                        subdirectories.append(DirectoryJob(node: child, path: path))
                    }
                case .file, .symlink, .other:
                    var size = parsed.allocatedSize
                    // Other links of a hard-linked file free no space when deleted.
                    if parsed.linkCount > 1, let fileID = parsed.fileID, !hardLinks.isFirstLink(fileID) {
                        size = 0
                    }
                    children.append(FileNode(name: parsed.name, kind: parsed.kind, size: size, parent: job.node))
                    fileCount += 1
                    byteCount += size
                }
            }
        }

        job.node.children = children
        progress.recordDirectory(path: job.path, files: fileCount, bytes: byteCount)
        return subdirectories
    }
}

/// One record of a `getattrlistbulk` result. Field order follows getattrlist(2):
/// returned-attributes set, error, name, then the remaining attributes by bit value
/// (common, directory, file), each 4-byte aligned.
private struct Entry {
    var name: String
    var kind: FileNode.Kind
    var fileID: UInt64?
    var isMountPoint = false
    var linkCount: UInt32 = 1
    var allocatedSize: Int64 = 0

    init?(at start: UnsafeRawPointer) {
        var field = start + MemoryLayout<UInt32>.size
        let returned = field.loadUnaligned(as: attribute_set_t.self)
        field += MemoryLayout<attribute_set_t>.size

        if returned.commonattr & Attr.error != 0 {
            let error = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
            if error != 0 { return nil }
        }

        guard returned.commonattr & Attr.name != 0 else { return nil }
        let nameReference = field.loadUnaligned(as: attrreference_t.self)
        name = String(cString: (field + Int(nameReference.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
        field += MemoryLayout<attrreference_t>.size

        kind = .other
        if returned.commonattr & Attr.objectType != 0 {
            let type = field.loadUnaligned(as: fsobj_type_t.self)
            field += MemoryLayout<fsobj_type_t>.size
            switch type {
            case fsobj_type_t(VDIR.rawValue): kind = .directory
            case fsobj_type_t(VREG.rawValue): kind = .file
            case fsobj_type_t(VLNK.rawValue): kind = .symlink
            default: kind = .other
            }
        }

        if returned.commonattr & Attr.fileID != 0 {
            fileID = field.loadUnaligned(as: UInt64.self)
            field += MemoryLayout<UInt64>.size
        }

        if returned.dirattr & Attr.mountStatus != 0 {
            let status = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
            isMountPoint = status & UInt32(DIR_MNTSTATUS_MNTPOINT | DIR_MNTSTATUS_TRIGGER) != 0
        }

        if returned.fileattr & Attr.linkCount != 0 {
            linkCount = field.loadUnaligned(as: UInt32.self)
            field += MemoryLayout<UInt32>.size
        }

        if returned.fileattr & Attr.allocatedSize != 0 {
            allocatedSize = field.loadUnaligned(as: off_t.self)
        }
    }
}

private enum Attr {
    static let returned = attrgroup_t(truncatingIfNeeded: ATTR_CMN_RETURNED_ATTRS)
    static let error = attrgroup_t(truncatingIfNeeded: ATTR_CMN_ERROR)
    static let name = attrgroup_t(truncatingIfNeeded: ATTR_CMN_NAME)
    static let objectType = attrgroup_t(truncatingIfNeeded: ATTR_CMN_OBJTYPE)
    static let fileID = attrgroup_t(truncatingIfNeeded: ATTR_CMN_FILEID)
    static let mountStatus = attrgroup_t(truncatingIfNeeded: ATTR_DIR_MOUNTSTATUS)
    static let linkCount = attrgroup_t(truncatingIfNeeded: ATTR_FILE_LINKCOUNT)
    static let allocatedSize = attrgroup_t(truncatingIfNeeded: ATTR_FILE_ALLOCSIZE)
}
