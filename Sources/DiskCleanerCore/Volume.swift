import Foundation

public struct Volume: Sendable, Identifiable, Hashable {
    public let url: URL
    public let name: String
    public let totalCapacity: Int64
    /// Free space excluding purgeable data.
    public let availableCapacity: Int64
    /// Free space including purgeable data the system can reclaim on demand.
    public let availableIncludingPurgeable: Int64
    public let isRoot: Bool
    public let isInternal: Bool
    public let format: String

    public var id: URL { url }
    public var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    public var purgeableCapacity: Int64 { max(0, availableIncludingPurgeable - availableCapacity) }

    /// Directory to scan. On the boot volume user data lives on the Data volume, while
    /// the sealed system volume cannot be changed anyway.
    public var scanPath: String {
        if isRoot, FileManager.default.fileExists(atPath: Self.dataVolumePath) {
            return Self.dataVolumePath
        }
        return url.path
    }

    static let dataVolumePath = "/System/Volumes/Data"

    public static func mounted() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsRootFileSystemKey,
            .volumeIsInternalKey, .volumeIsBrowsableKey, .volumeLocalizedFormatDescriptionKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) ?? []

        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable ?? true,
                  let total = values.volumeTotalCapacity, total > 0
            else { return nil }
            let available = Int64(values.volumeAvailableCapacity ?? 0)
            return Volume(
                url: url,
                name: values.volumeLocalizedName ?? url.lastPathComponent,
                totalCapacity: Int64(total),
                availableCapacity: available,
                availableIncludingPurgeable: max(available, values.volumeAvailableCapacityForImportantUsage ?? 0),
                isRoot: values.volumeIsRootFileSystem ?? false,
                isInternal: values.volumeIsInternal ?? false,
                format: values.volumeLocalizedFormatDescription ?? ""
            )
        }
        .sorted { lhs, rhs in
            lhs.isRoot != rhs.isRoot ? lhs.isRoot : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
