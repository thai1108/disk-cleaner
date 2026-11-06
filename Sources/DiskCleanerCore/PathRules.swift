import Foundation

public enum PathRules {
    /// Top-level folders of the boot volume that are firm-linked into the Data volume,
    /// read from /usr/share/firmlinks (e.g. "/Users", "/Applications").
    static let firmlinks: Set<String> = {
        guard let contents = try? String(contentsOfFile: "/usr/share/firmlinks", encoding: .utf8) else {
            return ["/Applications", "/Library", "/Users", "/Volumes", "/cores", "/opt", "/private", "/usr/local"]
        }
        let entries = contents.split(separator: "\n").compactMap { line in
            line.split(separator: "\t").first.map(String.init)
        }
        return Set(entries)
    }()

    /// The path users know: "/System/Volumes/Data/Users/me" becomes "/Users/me" when the
    /// Data volume folder is reachable through a firm link.
    public static func friendlyPath(_ path: String) -> String {
        let prefix = Volume.dataVolumePath
        guard path.hasPrefix(prefix + "/") else { return path == prefix ? "/" : path }
        let remainder = String(path.dropFirst(prefix.count))
        let isFirmlinked = firmlinks.contains { remainder == $0 || remainder.hasPrefix($0 + "/") }
        return isFirmlinked ? remainder : path
    }

    /// Maps a path the user sees (e.g. dropped from Finder) to the Data volume path.
    public static func dataVolumePath(for path: String) -> String {
        path.hasPrefix(Volume.dataVolumePath) ? path : Volume.dataVolumePath + path
    }

    /// Folders where macOS asks the user for consent ("… would like to access files in your
    /// Documents folder", Photos, Music) unless the app has Full Disk Access.
    public static func asksForConsent(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let name = (path as NSString).lastPathComponent
        if mediaLibraryExtensions.contains((name as NSString).pathExtension) { return true }
        guard consentFolders.contains(name) else { return false }
        return friendlyPath(path) == home + "/" + name
    }

    private static let consentFolders: Set<String> = ["Desktop", "Documents", "Downloads"]
    private static let mediaLibraryExtensions: Set<String> = ["photoslibrary", "musiclibrary", "tvlibrary"]

    /// Folders that must never be removed as a whole. Their contents can still be cleaned.
    public static func isProtected(_ path: String, home: String = NSHomeDirectory()) -> Bool {
        let normalized = friendlyPath(path)
        let isSystemContent = normalized.hasPrefix("/System/")
            || (normalized.hasPrefix("/usr/") && !normalized.hasPrefix("/usr/local/"))
        if isSystemContent || systemFolders.contains(normalized) { return true }
        let homeFolders = ["", "/Library", "/Desktop", "/Documents", "/Downloads", "/Movies", "/Music", "/Pictures", "/Public"]
        return homeFolders.contains { normalized == home + $0 }
    }

    private static let systemFolders: Set<String> = [
        "/", "/Applications", "/Library", "/System", "/Users", "/Volumes", "/bin", "/cores", "/dev",
        "/etc", "/opt", "/private", "/private/etc", "/private/tmp", "/private/var", "/sbin", "/tmp",
        "/usr", "/usr/local", "/var",
    ]
}
