import Testing
@testable import DiskCleanerCore

@Suite struct CleanupListTests {
    let root = TreeFixtures.tree("/data", [
        .dir("a", [.file("a1", 100), .file("a2", 300)]),
        .file("b", 200),
    ])

    @Test func ignoresItemsCoveredByQueuedAncestor() throws {
        var list = CleanupList()
        let a = try #require(root.descendant(atPath: "/data/a"))
        let a1 = try #require(root.descendant(atPath: "/data/a/a1"))

        list.add(a)
        list.add(a1)
        list.add(a)

        #expect(list.items.count == 1)
        #expect(list.contains(a1))
        #expect(list.totalSize == 400)
    }

    @Test func ancestorReplacesQueuedDescendants() throws {
        var list = CleanupList()
        list.add(try #require(root.descendant(atPath: "/data/a/a1")))
        list.add(try #require(root.descendant(atPath: "/data/b")))
        list.add(try #require(root.descendant(atPath: "/data/a")))

        #expect(list.items.map(\.name) == ["b", "a"])
        #expect(list.totalSize == 600)
    }

    @Test func removingAnItemDropsQueuedDescendants() throws {
        var list = CleanupList()
        let a = try #require(root.descendant(atPath: "/data/a"))
        list.add(try #require(root.descendant(atPath: "/data/a/a1")))
        list.add(try #require(root.descendant(atPath: "/data/a/a2")))
        list.add(try #require(root.descendant(atPath: "/data/b")))

        list.remove(a)

        #expect(list.items.map(\.name) == ["b"])
    }

    @Test func neverQueuesTheScanRoot() {
        var list = CleanupList()
        list.add(root)
        #expect(list.isEmpty)
    }
}
