import Foundation
import Testing
@testable import DiskCleanerCore

@Suite struct DiskScannerTests {
    /// Creates a scratch directory tree and removes it when the test ends.
    final class Sandbox {
        let url: URL

        init() throws {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("DiskScannerTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }

        func write(_ relativePath: String, bytes: Int) throws {
            let file = url.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0xAB, count: bytes).write(to: file)
        }

        func allocatedSize(_ relativePath: String) throws -> Int64 {
            let values = try url.appendingPathComponent(relativePath).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            return Int64(try #require(values.totalFileAllocatedSize))
        }
    }

    @Test func buildsTreeWithAllocatedSizes() throws {
        let sandbox = try Sandbox()
        try sandbox.write("big.bin", bytes: 1_000_000)
        try sandbox.write("nested/inner/small.txt", bytes: 10)
        try sandbox.write("nested/medium.bin", bytes: 100_000)
        let expected = try sandbox.allocatedSize("big.bin")
            + sandbox.allocatedSize("nested/inner/small.txt")
            + sandbox.allocatedSize("nested/medium.bin")

        let progress = ScanProgress()
        let root = try DiskScanner.scanBlocking(path: sandbox.url.path, progress: progress)

        #expect(root.size == expected)
        #expect(root.fileCount == 3)
        #expect(root.children.map(\.name) == ["big.bin", "nested"])
        #expect(root.descendant(atPath: sandbox.url.path + "/nested/inner/small.txt")?.kind == .file)
        #expect(progress.filesScanned == 3)
        #expect(progress.directoriesScanned == 3)
        #expect(progress.bytesScanned == expected)
    }

    @Test func countsHardLinkedFileOnce() throws {
        let sandbox = try Sandbox()
        try sandbox.write("original.bin", bytes: 500_000)
        try FileManager.default.linkItem(
            at: sandbox.url.appendingPathComponent("original.bin"),
            to: sandbox.url.appendingPathComponent("link.bin")
        )

        let root = try DiskScanner.scanBlocking(path: sandbox.url.path)

        #expect(root.size == (try sandbox.allocatedSize("original.bin")))
        #expect(root.fileCount == 2)
    }

    @Test func doesNotFollowSymlinks() throws {
        let sandbox = try Sandbox()
        try sandbox.write("target/data.bin", bytes: 200_000)
        try FileManager.default.createSymbolicLink(
            at: sandbox.url.appendingPathComponent("alias"),
            withDestinationURL: sandbox.url.appendingPathComponent("target")
        )

        let root = try DiskScanner.scanBlocking(path: sandbox.url.path)

        let alias = root.children.first { $0.name == "alias" }
        #expect(alias?.kind == .symlink)
        #expect(alias?.children.isEmpty == true)
        #expect(root.size < 2 * (try sandbox.allocatedSize("target/data.bin")))
    }

    @Test func marksUnreadableDirectories() throws {
        let sandbox = try Sandbox()
        try sandbox.write("locked/secret.bin", bytes: 10)
        let locked = sandbox.url.appendingPathComponent("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

        let progress = ScanProgress()
        let root = try DiskScanner.scanBlocking(path: sandbox.url.path, progress: progress)

        #expect(root.children.first?.isUnreadable == true)
        #expect(progress.unreadableDirectories == 1)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/System/Volumes/Data")))
    func skipsMountPointsOfOtherVolumes() throws {
        let root = try DiskScanner.scanBlocking(path: "/System/Volumes")

        #expect(!root.isUnreadable)
        #expect(!root.children.contains { $0.name == "Data" })
    }

    @Test func throwsForMissingPath() {
        #expect(throws: ScanError.notFound("/no/such/path")) {
            try DiskScanner.scanBlocking(path: "/no/such/path")
        }
    }

    @Test func stopsWhenCancelled() {
        #expect(throws: CancellationError.self) {
            try DiskScanner.scanBlocking(path: "/usr", isCancelled: { true })
        }
    }

    @Test func listsButDoesNotEnterSkippedDirectories() throws {
        let sandbox = try Sandbox()
        try sandbox.write("keep/a.bin", bytes: 10)
        try sandbox.write("private/b.bin", bytes: 10)
        let progress = ScanProgress()
        var options = ScanOptions()
        options.skipsDirectory = { $0.hasSuffix("/private") }

        let root = try DiskScanner.scanBlocking(path: sandbox.url.path, options: options, progress: progress)

        let skipped = try #require(root.children.first { $0.name == "private" })
        #expect(skipped.isUnreadable)
        #expect(skipped.children.isEmpty)
        #expect(root.children.first { $0.name == "keep" }?.children.count == 1)
        #expect(progress.unreadableDirectories == 1)
    }

    /// Temp dirs live under the `/var` → `/private/var` symlink, so both spellings exist.
    @Test func findsNodesForURLsSpelledEitherWay() throws {
        let sandbox = try Sandbox()
        try sandbox.write("nested/medium.bin", bytes: 10)
        let resolved = try #require(realpath(sandbox.url.path, nil))
        defer { free(resolved) }
        let privatePath = String(cString: resolved)
        let symlinkedPath = String(privatePath.dropFirst("/private".count))
        try #require(privatePath.hasPrefix("/private/var/"))

        let privateRoot = try DiskScanner.scanBlocking(path: privatePath)
        let fromList = privateRoot.descendant(at: URL(fileURLWithPath: privatePath + "/nested/medium.bin"))
        #expect(fromList?.name == "medium.bin")

        let symlinkedRoot = try DiskScanner.scanBlocking(path: symlinkedPath)
        let fromFinder = symlinkedRoot.descendant(at: URL(fileURLWithPath: privatePath + "/nested"))
        #expect(fromFinder?.path == symlinkedPath + "/nested")
        #expect(symlinkedRoot.descendant(at: URL(fileURLWithPath: privatePath)) === symlinkedRoot)
        #expect(symlinkedRoot.descendant(at: URL(fileURLWithPath: "/usr/bin")) == nil)
    }
}
