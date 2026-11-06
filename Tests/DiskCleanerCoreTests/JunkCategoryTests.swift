import Foundation
import Testing
@testable import DiskCleanerCore

@Suite struct JunkCategoryTests {
    private func category(_ id: String) throws -> JunkCategory {
        try #require(JunkCategory.all.first { $0.id == id })
    }

    @Test func measuresContentsWithoutExcludedSubfolders() throws {
        let home = try DiskScannerTests.Sandbox()
        try home.write("Library/Caches/com.example/blob", bytes: 40_000)
        try home.write("Library/Caches/Homebrew/bottle.tar.gz", bytes: 80_000)
        let blob = try home.allocatedSize("Library/Caches/com.example/blob")

        #expect(try category("appCaches").measure(home: home.url.path) == blob)
        #expect(try category("homebrew").measure(home: home.url.path) == home.allocatedSize("Library/Caches/Homebrew/bottle.tar.gz"))
    }

    @Test func missingFoldersMeanTheCategoryDoesNotApply() throws {
        let home = try DiskScannerTests.Sandbox()
        #expect(try category("gradle").measure(home: home.url.path) == nil)
    }

    @Test func unreadableFoldersDoNotCount() throws {
        let home = try DiskScannerTests.Sandbox()
        try home.write("Library/Logs/app.log", bytes: 10)
        let logs = home.url.path + "/Library/Logs"
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: logs)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: logs) }

        #expect(try category("logs").measure(home: home.url.path) == nil)
    }

    @Test func cleaningKeepsTheFolderAndExcludedSubfolders() throws {
        let home = try DiskScannerTests.Sandbox()
        try home.write("Library/Caches/com.example/blob", bytes: 10)
        try home.write("Library/Caches/loose.db", bytes: 10)
        try home.write("Library/Caches/Homebrew/bottle.tar.gz", bytes: 10)

        #expect(try category("appCaches").clean(home: home.url.path).isEmpty)

        let caches = home.url.path + "/Library/Caches"
        #expect(try FileManager.default.contentsOfDirectory(atPath: caches) == ["Homebrew"])
        #expect(FileManager.default.fileExists(atPath: caches + "/Homebrew/bottle.tar.gz"))
    }
}
