import Foundation
import Observation
import Sparkle

/// Sparkle's updater for SwiftUI. It reads the appcast in Info.plist (`SUFeedURL`) once a day
/// and, by default, downloads and installs new versions in the background.
@MainActor @Observable
final class Updater {
    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    private(set) var canCheckForUpdates = false

    /// "1.2.0 (3)", from the bundle's version and build number.
    static let versionDescription: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        return (info["CFBundleVersion"] as? String).map { "\(version) (\($0))" } ?? version
    }()

    init() {
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) {
            [weak self] _, change in
            let canCheck = change.newValue ?? false
            // Sparkle changes this on the main thread.
            MainActor.assumeIsolated { self?.canCheckForUpdates = canCheck }
        }
    }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
        }
    }

    var automaticallyInstalls: Bool {
        get {
            access(keyPath: \.automaticallyInstalls)
            return controller.updater.automaticallyDownloadsUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyInstalls) {
                controller.updater.automaticallyDownloadsUpdates = newValue
            }
        }
    }

    var lastCheck: Date? {
        controller.updater.lastUpdateCheckDate
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
