import AppKit
import SwiftUI

@main
struct DiskCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        Window("Disk Cleaner", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Scan Folder…") { model.isChoosingFolder = true }
                    .keyboardShortcut("o")
                Button(model.selectedAnalysis == nil ? "Scan" : "Rescan") { model.rescanSelection() }
                    .keyboardShortcut("r")
                    .disabled(model.selectedTarget == nil)
                Divider()
                Button("Empty Trash…") { model.requestEmptyTrash() }
                    .keyboardShortcut(.delete, modifiers: [.command, .shift])
            }
            TrashCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (e.g. `swift run`) rather than an .app bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Folders dropped on the Dock icon or passed via `open -a "Disk Cleaner" <folder>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let folder = urls.first(where: \.hasDirectoryPath) {
            model.scan(ScanTarget(folder: folder))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppTheme.storageKey) private var theme: AppTheme = .teal

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            DetailView()
        }
        .fileImporter(isPresented: $model.isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                model.scan(ScanTarget(folder: url))
            }
        }
        .sheet(isPresented: Binding(
            get: { model.targetAwaitingAccess != nil },
            set: { if !$0 { model.targetAwaitingAccess = nil } }
        )) {
            FullDiskAccessSheet()
        }
        .alert(
            "Scan failed",
            isPresented: Binding(get: { model.scanError != nil }, set: { if !$0 { model.scanError = nil } }),
            presenting: model.scanError
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .alert(
            model.trashToEmpty?.itemCount == 0 ? "The Trash is empty" : "Empty the Trash?",
            isPresented: Binding(get: { model.trashToEmpty != nil }, set: { if !$0 { model.trashToEmpty = nil } }),
            presenting: model.trashToEmpty
        ) { summary in
            if summary.itemCount > 0 {
                Button("Empty Trash", role: .destructive) { Task { await model.emptyTrash() } }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { summary in
            if summary.itemCount > 0 {
                Text("\(summary.itemCount.formatted()) items (\(summary.size.byteString)) will be erased permanently. This can't be undone.")
            }
        }
        .alert(
            "Some items could not be removed from the Trash",
            isPresented: Binding(get: { !model.trashFailures.isEmpty }, set: { if !$0 { model.trashFailures = [] } })
        ) {
            Button("OK") {}
        } message: {
            Text(model.trashFailures.joined(separator: "\n"))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
        .environment(\.theme, theme)
    }
}

/// Scan progress, results, or an overview for whatever the sidebar has selected.
private struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.selection == AppModel.quickCleanID {
            QuickCleanView(quickClean: model.quickClean)
        } else if let session = model.activeScan, session.target.path == model.selection {
            ScanningView(session: session)
        } else if let analysis = model.selectedAnalysis {
            ResultsView(analysis: analysis)
                .id(ObjectIdentifier(analysis))
        } else if let target = model.selectedTarget {
            OverviewView(target: target)
        } else {
            ContentUnavailableView("Choose a Disk or Folder", systemImage: "internaldrive",
                                   description: Text("Pick a location in the sidebar to see what takes up space."))
        }
    }
}
