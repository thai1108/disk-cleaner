import Testing
@testable import DiskCleanerCore

@Suite struct BreakdownTests {
    @Test func partsAreProportionalAndLargestFirst() {
        let root = TreeFixtures.tree("/data", [
            .dir("a", [.file("a1", 250), .file("a2", 250)]),
            .file("b", 300),
            .file("c", 200),
        ])
        let parts = Breakdown(of: root).parts

        #expect(parts.map { $0.node?.name } == ["a", "b", "c"])
        #expect(parts.map(\.fraction) == [0.5, 0.3, 0.2])
        #expect(parts.map(\.id) == [0, 1, 2])
    }

    @Test func mergesTinyItemsIntoOnePart() throws {
        let tiny = (0..<50).map { TreeFixtures.Spec.file("t\($0)", 1) }
        let root = TreeFixtures.tree("/data", [.file("big", 10_000)] + tiny)
        let parts = Breakdown(of: root, minimumFraction: 0.01).parts

        #expect(parts.count == 2)
        guard case .otherItems(let count) = try #require(parts.last).content else {
            Issue.record("expected merged items")
            return
        }
        #expect(count == 50)
        #expect(parts[1].size == 50)
    }

    @Test func limitsTheNumberOfSeparateParts() {
        let root = TreeFixtures.tree("/data", (0..<12).map { .file("f\($0)", 100) })
        let parts = Breakdown(of: root, maxParts: 8).parts

        #expect(parts.count == 9)
        #expect(parts.last?.size == 400)
        #expect(abs(parts.reduce(0) { $0 + $1.fraction } - 1) < 1e-9)
    }

    @Test func emptyFolderHasNoParts() {
        let root = TreeFixtures.tree("/data", [.dir("empty", [])])
        #expect(Breakdown(of: root).parts.isEmpty)
    }
}
