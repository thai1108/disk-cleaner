import AppKit
import DiskCleanerCore
import Observation

struct ScanTarget: Equatable {
    let title: String
    let path: String
    let volume: Volume?

    init(volume: Volume) {
        title = volume.name
        path = volume.scanPath
        self.volume = volume
    }

    init(folder: URL) {
        title = FileManager.default.displayName(atPath: folder.path)
        path = folder.path
        volume = nil
    }

    static var home: ScanTarget { ScanTarget(folder: FileManager.default.homeDirectoryForCurrentUser) }
}

@MainActor
final class ScanSession {
    let target: ScanTarget
    let progress = ScanProgress()
    let startedAt = Date()
    var task: Task<Void, Never>?

    init(target: ScanTarget) {
        self.target = target
    }

    /// Fraction of the volume's used space scanned so far; nil for folder scans.
    var estimatedFraction: Double? {
        guard let used = target.volume?.usedCapacity, used > 0 else { return nil }
        return min(0.99, Double(progress.bytesScanned) / Double(used))
    }
}

/// Disks and folders in the sidebar, the scan in progress, and every finished scan of the
/// session, keyed by path so switching between locations never throws results away.
@MainActor @Observable
final class AppModel {
    private(set) var volumes: [Volume] = Volume.mounted()
    /// Home plus every other folder scanned this session.
    private(set) var folders: [ScanTarget] = [.home]
    private(set) var finishedScans: [String: Analysis] = [:]
    private(set) var activeScan: ScanSession?
    private(set) var hasFullDiskAccess = FullDiskAccess.isGranted
    let quickClean = QuickClean()
    let updater = Updater()
    /// Path of the location selected in the sidebar.
    var selection: String?
    var isChoosingFolder = false
    var scanError: String?
    /// Scan waiting for the one-time Full Disk Access explanation to be answered.
    var targetAwaitingAccess: ScanTarget?
    /// What is in the Trash while asking whether to empty it.
    var trashToEmpty: TrashFolder.Summary?
    var trashFailures: [String] = []

    private static let explainedAccessKey = "explainedFullDiskAccess"
    /// Sidebar selection for the Quick Clean tool, which is not a disk or folder.
    static let quickCleanID = "tool:quick-clean"

    init() {
        selection = volumes.first?.scanPath ?? ScanTarget.home.path
        quickClean.onSpaceChanged = refreshHandler
        quickClean.onTrashEmptied = { [weak self] in
            self?.finishedScans.values.forEach { $0.trashWasEmptied() }
        }
    }

    var selectedTarget: ScanTarget? {
        guard let selection else { return nil }
        if let volume = volumes.first(where: { $0.scanPath == selection }) {
            return ScanTarget(volume: volume)
        }
        return folders.first { $0.path == selection }
    }

    var selectedAnalysis: Analysis? {
        selection.flatMap { finishedScans[$0] }
    }

    func isScanning(_ path: String) -> Bool {
        activeScan?.target.path == path
    }

    /// Re-reads volumes and access after the app comes back to the front.
    func refresh() {
        volumes = Volume.mounted()
        hasFullDiskAccess = FullDiskAccess.isGranted
    }

    /// Explains Full Disk Access once, before the first scan without it; later scans go ahead
    /// and skip the folders macOS would otherwise ask about one by one.
    func scan(_ target: ScanTarget) {
        if target.volume == nil, !folders.contains(where: { $0.path == target.path }) {
            folders.append(target)
        }
        selection = target.path
        hasFullDiskAccess = FullDiskAccess.isGranted
        let defaults = UserDefaults.standard
        guard hasFullDiskAccess || defaults.bool(forKey: Self.explainedAccessKey) else {
            defaults.set(true, forKey: Self.explainedAccessKey)
            targetAwaitingAccess = target
            return
        }
        startScan(target)
    }

    func rescanSelection() {
        if let selectedTarget { scan(selectedTarget) }
    }

    /// Answer to the Full Disk Access explanation: scan now, without the protected folders.
    func scanWithoutFullDiskAccess() {
        guard let target = targetAwaitingAccess else { return }
        targetAwaitingAccess = nil
        startScan(target)
    }

    func cancelScan() {
        activeScan?.task?.cancel()
        activeScan = nil
    }

    /// Frees a scan's memory; folders other than Home also leave the sidebar.
    func remove(_ target: ScanTarget) {
        if isScanning(target.path) { cancelScan() }
        finishedScans[target.path] = nil
        guard target.volume == nil, target.path != ScanTarget.home.path else { return }
        folders.removeAll { $0.path == target.path }
        if selection == target.path { selection = volumes.first?.scanPath }
    }

    /// Measures the Trash and asks before emptying it. Without Full Disk Access the Trash
    /// can't be read, so it opens in Finder instead.
    func requestEmptyTrash() {
        Task {
            let summary = await Task.detached(priority: .userInitiated) { try? TrashFolder.measure() }.value
            if let summary {
                trashToEmpty = summary
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: TrashFolder.path()))
            }
        }
    }

    func emptyTrash() async {
        trashToEmpty = nil
        trashFailures = await Task.detached(priority: .userInitiated) { TrashFolder.empty() }.value
        finishedScans.values.forEach { $0.trashWasEmptied() }
        refresh()
    }

    /// Held weakly so that finished scans don't keep the model alive.
    private var refreshHandler: () -> Void {
        { [weak self] in self?.refresh() }
    }

    private func startScan(_ target: ScanTarget) {
        cancelScan()
        var options = ScanOptions()
        if !hasFullDiskAccess {
            let home = NSHomeDirectory()
            options.skipsDirectory = { PathRules.asksForConsent($0, home: home) }
        }
        let session = ScanSession(target: target)
        activeScan = session
        session.task = Task {
            do {
                let root = try await DiskScanner.scan(path: target.path, options: options, progress: session.progress)
                guard activeScan === session else { return }
                let analysis = Analysis(
                    target: target,
                    root: root,
                    unreadableCount: session.progress.unreadableDirectories,
                    duration: Date().timeIntervalSince(session.startedAt)
                )
                analysis.onSpaceChanged = refreshHandler
                finishedScans[target.path] = analysis
                activeScan = nil
            } catch is CancellationError {
                // `cancelScan` already cleared the session.
            } catch {
                guard activeScan === session else { return }
                activeScan = nil
                scanError = error.localizedDescription
            }
        }
    }
}
