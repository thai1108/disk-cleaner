import Foundation
import Testing
@testable import DiskCleanerCore

@Suite struct TrashFolderTests {
    @Test func measuresAndEmptiesTheTrash() throws {
        let home = try DiskScannerTests.Sandbox()
        try home.write(".Trash/old.dmg", bytes: 50_000)
        try home.write(".Trash/project/file.txt", bytes: 10)
        try home.write("Documents/keep.txt", bytes: 10)

        let summary = try TrashFolder.measure(home: home.url.path)
        #expect(summary.itemCount == 2)
        #expect(summary.size >= 50_000)

        #expect(TrashFolder.empty(home: home.url.path).isEmpty)
        #expect(try TrashFolder.measure(home: home.url.path) == .init(itemCount: 0, size: 0))
        #expect(FileManager.default.fileExists(atPath: home.url.path + "/.Trash"))
        #expect(FileManager.default.fileExists(atPath: home.url.path + "/Documents/keep.txt"))
    }

    @Test func measuringAMissingTrashThrows() throws {
        let home = try DiskScannerTests.Sandbox()
        #expect(throws: ScanError.self) { try TrashFolder.measure(home: home.url.path) }
    }
}
