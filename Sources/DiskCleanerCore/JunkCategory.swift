import Foundation

/// Folders holding only data that apps rebuild on demand, so their contents are safe to delete.
public struct JunkCategory: Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let detail: String
    /// Folders, relative to the home folder, whose contents get cleaned.
    public let folders: [String]
    /// Subfolders, relative to the home folder, left to another category.
    public let excluded: [String]

    public static let all: [JunkCategory] = [
        JunkCategory(id: "trash", title: "Trash", detail: "Files you already deleted.",
                     folders: [".Trash"]),
        JunkCategory(id: "appCaches", title: "App Caches",
                     detail: "Temporary data apps recreate when needed. Quit apps first for best results.",
                     folders: ["Library/Caches"], excluded: ["Library/Caches/Homebrew"]),
        JunkCategory(id: "logs", title: "Logs", detail: "Diagnostic logs written by apps.",
                     folders: ["Library/Logs"]),
        JunkCategory(id: "derivedData", title: "Xcode Build Data",
                     detail: "DerivedData: intermediate build products, rebuilt on the next build.",
                     folders: ["Library/Developer/Xcode/DerivedData"]),
        JunkCategory(id: "deviceSupport", title: "Xcode Device Support",
                     detail: "Debug symbols copied from devices, copied again when a device connects.",
                     folders: ["Library/Developer/Xcode/iOS DeviceSupport",
                               "Library/Developer/Xcode/watchOS DeviceSupport",
                               "Library/Developer/Xcode/tvOS DeviceSupport"]),
        JunkCategory(id: "simulatorCaches", title: "Simulator Caches", detail: "Caches of the iOS Simulator.",
                     folders: ["Library/Developer/CoreSimulator/Caches"]),
        JunkCategory(id: "homebrew", title: "Homebrew Downloads",
                     detail: "Downloaded bottles and source archives of installed packages.",
                     folders: ["Library/Caches/Homebrew"]),
        JunkCategory(id: "npm", title: "npm Cache", detail: "Packages npm downloads again when needed.",
                     folders: [".npm/_cacache"]),
        JunkCategory(id: "gradle", title: "Gradle Caches", detail: "Dependencies and build caches of Gradle.",
                     folders: [".gradle/caches"]),
    ]

    init(id: String, title: String, detail: String, folders: [String], excluded: [String] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.folders = folders
        self.excluded = excluded
    }

    /// Size of the folders' contents, or nil when none of them exist or can be read.
    public func measure(home: String = NSHomeDirectory()) -> Int64? {
        let roots = folders
            .compactMap { try? DiskScanner.scanBlocking(path: home + "/" + $0) }
            .filter { !$0.isUnreadable }
        guard !roots.isEmpty else { return nil }
        let excludedSize = excluded
            .compactMap { path in roots.lazy.compactMap { $0.descendant(atPath: home + "/" + path) }.first }
            .reduce(0) { $0 + $1.size }
        return roots.reduce(0) { $0 + $1.size } - excludedSize
    }

    /// Deletes the folders' contents, keeping the folders themselves. Returns what failed.
    public func clean(home: String = NSHomeDirectory()) -> [String] {
        let skipped = Set(excluded.map { home + "/" + $0 })
        var failures: [String] = []
        for folder in folders.map({ home + "/" + $0 }) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where !skipped.contains(folder + "/" + name) {
                do {
                    try FileManager.default.removeItem(atPath: folder + "/" + name)
                } catch {
                    failures.append("\(name): \(error.localizedDescription)")
                }
            }
        }
        return failures
    }
}
