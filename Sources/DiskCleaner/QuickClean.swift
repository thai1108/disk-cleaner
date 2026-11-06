import DiskCleanerCore
import Foundation
import Observation

/// Sizes of the junk categories present on this Mac, which of them to clean, and the result.
@MainActor @Observable
final class QuickClean {
    struct Result {
        let freed: Int64
        let failures: [String]
    }

    /// Only categories whose folders exist on this Mac and can be read.
    private(set) var sizes: [JunkCategory.ID: Int64] = [:]
    private(set) var isMeasuring = false
    private(set) var isCleaning = false
    private(set) var lastResult: Result?
    /// The Trash is left out by default: emptying it can't be undone.
    var selected: Set<JunkCategory.ID> = Set(JunkCategory.all.map(\.id)).subtracting(["trash"])

    var onSpaceChanged: (() -> Void)?
    var onTrashEmptied: (() -> Void)?

    /// Categories with something to clean.
    var available: [JunkCategory] {
        JunkCategory.all.filter { (sizes[$0.id] ?? 0) > 0 }
    }

    var selectedSize: Int64 {
        available.filter { selected.contains($0.id) }.reduce(0) { $0 + (sizes[$1.id] ?? 0) }
    }

    var totalSize: Int64 {
        sizes.values.reduce(0, +)
    }

    func measure() async {
        guard !isMeasuring else { return }
        isMeasuring = true
        defer { isMeasuring = false }
        let home = NSHomeDirectory()
        sizes = await withTaskGroup(of: (JunkCategory.ID, Int64?).self) { group in
            for category in JunkCategory.all {
                group.addTask { (category.id, category.measure(home: home)) }
            }
            var sizes: [JunkCategory.ID: Int64] = [:]
            for await (id, size) in group {
                sizes[id] = size
            }
            return sizes
        }
    }

    func cleanSelected() async {
        let categories = available.filter { selected.contains($0.id) && (sizes[$0.id] ?? 0) > 0 }
        guard !categories.isEmpty, !isCleaning else { return }
        isCleaning = true
        let before = selectedSize
        let home = NSHomeDirectory()
        let failures = await Task.detached(priority: .userInitiated) {
            categories.flatMap { $0.clean(home: home) }
        }.value
        isCleaning = false
        await measure()
        let after = categories.reduce(0) { $0 + (sizes[$1.id] ?? 0) }
        lastResult = Result(freed: max(0, before - after), failures: failures)
        if categories.contains(where: { $0.id == "trash" }) { onTrashEmptied?() }
        onSpaceChanged?()
    }

    func dismissResult() {
        lastResult = nil
    }
}
