import Testing
@testable import DiskCleanerCore

@Suite struct PathRulesTests {
    @Test func stripsDataVolumePrefixOnlyForFirmlinkedFolders() {
        #expect(PathRules.friendlyPath("/System/Volumes/Data/Users/me/file") == "/Users/me/file")
        #expect(PathRules.friendlyPath("/System/Volumes/Data") == "/")
        #expect(PathRules.friendlyPath("/System/Volumes/Data/.Spotlight-V100") == "/System/Volumes/Data/.Spotlight-V100")
        #expect(PathRules.friendlyPath("/Volumes/USB/file") == "/Volumes/USB/file")
    }

    @Test func mapsFinderPathsToDataVolume() {
        #expect(PathRules.dataVolumePath(for: "/Users/me") == "/System/Volumes/Data/Users/me")
        #expect(PathRules.dataVolumePath(for: "/System/Volumes/Data/Users/me") == "/System/Volumes/Data/Users/me")
    }

    @Test func detectsFoldersMacOSAsksConsentFor() {
        let home = "/Users/me"
        #expect(PathRules.asksForConsent("/Users/me/Documents", home: home))
        #expect(PathRules.asksForConsent("/System/Volumes/Data/Users/me/Downloads", home: home))
        #expect(PathRules.asksForConsent("/Users/me/Pictures/Photos Library.photoslibrary", home: home))
        #expect(PathRules.asksForConsent("/Users/me/Music/Music/Music Library.musiclibrary", home: home))

        #expect(!PathRules.asksForConsent("/Users/me/Projects/Documents", home: home))
        #expect(!PathRules.asksForConsent("/Users/other/Desktop", home: home))
        #expect(!PathRules.asksForConsent("/Users/me/Pictures", home: home))
    }

    @Test func protectsSystemAndHomeFolders() {
        let home = "/Users/me"
        #expect(PathRules.isProtected("/System/Volumes/Data/Users", home: home))
        #expect(PathRules.isProtected("/System/Volumes/Data/Users/me", home: home))
        #expect(PathRules.isProtected("/Users/me/Library", home: home))
        #expect(PathRules.isProtected("/Users/me/Downloads", home: home))
        #expect(PathRules.isProtected("/usr/bin", home: home))
        #expect(PathRules.isProtected("/System/Library/Caches", home: home))

        #expect(!PathRules.isProtected("/Users/me/Downloads/big.dmg", home: home))
        #expect(!PathRules.isProtected("/Users/me/Library/Caches", home: home))
        #expect(!PathRules.isProtected("/usr/local/Cellar", home: home))
        #expect(!PathRules.isProtected("/Applications/Foo.app", home: home))
    }
}
