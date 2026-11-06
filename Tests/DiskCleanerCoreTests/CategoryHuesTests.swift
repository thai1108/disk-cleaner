import Testing
@testable import DiskCleanerCore

@Suite struct CategoryHuesTests {
    @Test func neutralThemeKeepsTheBaseHues() {
        #expect(CategoryHues.hues(leadingWith: nil) == CategoryHues.base)
    }

    @Test func accentLeadsAndCloseHuesAreDropped() {
        let hues = CategoryHues.hues(leadingWith: 0.50)
        #expect(hues.first == 0.50)
        #expect(!hues.contains(0.49))
        #expect(hues.contains(0.58))
        #expect(hues.count == CategoryHues.base.count)
    }

    @Test func closenessWrapsAroundTheColorWheel() {
        let hues = CategoryHues.hues(leadingWith: 0.99)
        #expect(!hues.contains(0.02))
        #expect(hues.contains(0.92))
    }
}
