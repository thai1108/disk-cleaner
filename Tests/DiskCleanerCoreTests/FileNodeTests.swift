import Testing
@testable import DiskCleanerCore

@Suite struct FileNodeTests {
    let root = TreeFixtures.tree("/data", [
        .dir("a", [.file("a1", 100), .file("a2", 300), .dir("deep", [.file("d1", 50)])]),
        .file("b", 200),
        .dir("empty", []),
    ])

    @Test func rollsUpSizesAndCounts() {
        #expect(root.size == 650)
        #expect(root.fileCount == 4)
        #expect(root.children.map(\.name) == ["a", "b", "empty"])
        #expect(root.children[0].children.map(\.name) == ["a2", "a1", "deep"])
    }

    @Test func derivesPathsFromAncestors() throws {
        let d1 = try #require(root.descendant(atPath: "/data/a/deep/d1"))
        #expect(d1.path == "/data/a/deep/d1")
        #expect(d1.ancestors.map(\.name) == ["data", "a", "deep"])
        #expect(d1.isDescendant(of: root))
        #expect(!root.isDescendant(of: d1))
        #expect(root.descendant(atPath: "/data") === root)
        #expect(root.descendant(atPath: "/data/missing") == nil)
        #expect(root.descendant(atPath: "/elsewhere/a") == nil)
    }

    @Test func rootPathOfFilesystemRoot() {
        let slash = TreeFixtures.tree("/", [.file("x", 1)])
        #expect(slash.children[0].path == "/x")
    }

    @Test func removingSubtractsFromAncestorsAndResorts() throws {
        let a2 = try #require(root.descendant(atPath: "/data/a/a2"))
        a2.removeFromParent()

        let a = root.children.first { $0.name == "a" }
        #expect(a?.size == 150)
        #expect(a?.fileCount == 2)
        #expect(root.size == 350)
        #expect(root.fileCount == 3)
        #expect(a2.parent == nil)
        // "a" (150) is now smaller than "b" (200).
        #expect(root.children.map(\.name) == ["b", "a", "empty"])
    }

    @Test func reattachingRestoresSizesAndOrder() throws {
        let a = try #require(root.descendant(atPath: "/data/a"))
        let a2 = try #require(root.descendant(atPath: "/data/a/a2"))
        let sizeBefore = root.size
        let orderBefore = root.children.map(\.name)

        a2.removeFromParent()
        a2.reattach(to: a)

        #expect(root.size == sizeBefore)
        #expect(a.fileCount == 3)
        #expect(a2.parent === a)
        #expect(a2.path == "/data/a/a2")
        #expect(root.children.map(\.name) == orderBefore)
    }
}
