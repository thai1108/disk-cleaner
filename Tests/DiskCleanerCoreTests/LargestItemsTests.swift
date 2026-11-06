import Testing
@testable import DiskCleanerCore

@Suite struct LargestItemsTests {
    let root = TreeFixtures.tree("/data", [
        .dir("Movies", [.file("trip.MOV", 900), .file("notes.txt", 50)]),
        .dir("Downloads", [.file("Xcode.xip", 700), .file("setup.dmg", 400), .file("photo.jpg", 30)]),
        .dir("Big.app", [.dir("Contents", [.file("binary", 600), .file("asset", 500)])]),
        .file("archive.zip", 300),
    ])

    @Test func findsTheLargestItemsAcrossFolders() {
        #expect(root.largestItems(limit: 3).map(\.name) == ["Big.app", "trip.MOV", "Xcode.xip"])
    }

    @Test func packagesCountAsOneItem() {
        let names = root.largestItems(limit: 100).map(\.name)
        #expect(names.contains("Big.app"))
        #expect(!names.contains("binary"))
    }

    @Test func filtersByKind() {
        #expect(root.largestItems(limit: 10, kind: .video).map(\.name) == ["trip.MOV"])
        #expect(root.largestItems(limit: 10, kind: .installer).map(\.name) == ["Xcode.xip"])
        #expect(root.largestItems(limit: 10, kind: .diskImage).map(\.name) == ["setup.dmg"])
        #expect(root.largestItems(limit: 10, kind: .application).map(\.name) == ["Big.app"])
    }

    @Test func classifiesByExtensionIgnoringCase() {
        #expect(FileKind(fileName: "Clip.MP4") == .video)
        #expect(FileKind(fileName: "backup.tar.gz") == .archive)
        #expect(FileKind(fileName: "README") == nil)
    }
}
