import DiskCleanerCore
import QuickLook
import SwiftUI

struct ResultsView: View {
    @Environment(AppModel.self) private var model
    @Bindable var analysis: Analysis

    var body: some View {
        VStack(spacing: 0) {
            SummaryCard(analysis: analysis)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)
            ListModeBar(analysis: analysis)
            // The lists scroll under the floating cleanup bar.
            switch analysis.listMode {
            case .contents: ItemList(analysis: analysis)
            case .largest: LargestItemsList(analysis: analysis)
            }
        }
        .background(Backdrop())
        .safeAreaInset(edge: .top, spacing: 0) {
            Breadcrumb(analysis: analysis)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if let report = analysis.lastCleanup {
                    CleanupToast(report: report, analysis: analysis)
                        .padding(.top, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                CleanupBar(analysis: analysis)
            }
            .animation(.smooth(duration: 0.3), value: analysis.lastCleanup?.id)
        }
        .navigationTitle(analysis.target.title)
        .navigationSubtitle("\(analysis.totalSize.byteString) · \(analysis.totalFileCount.formatted()) files")
        .quickLookPreview($analysis.quickLookURL)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Enclosing Folder", systemImage: "chevron.up") {
                    withAnimation(.easeOut(duration: 0.45)) { analysis.focusParent() }
                }
                .disabled(analysis.focused.parent == nil)
                .keyboardShortcut(.upArrow, modifiers: .command)
                .help("Go to the enclosing folder (⌘↑)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open in Finder", systemImage: "folder") { analysis.showInFinder(analysis.focused) }
                    .help("Open \(analysis.focused.name) in Finder")
                Button("Rescan", systemImage: "arrow.clockwise") { model.rescanSelection() }
                    .help("Scan again (⌘R)")
            }
        }
        .alert(
            "Some items could not be removed",
            isPresented: Binding(
                get: { !analysis.deletionFailures.isEmpty },
                set: { if !$0 { analysis.deletionFailures = [] } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(analysis.deletionFailures.joined(separator: "\n"))
        }
    }
}

/// Path from the scan root to the focused folder, as a glass path bar.
private struct Breadcrumb: View {
    @Environment(\.theme) private var theme
    let analysis: Analysis

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(analysis.breadcrumb.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    crumb(node, title: index == 0 ? analysis.target.title : node.name)
                }
            }
            .padding(4)
        }
        .glassBackground(in: .capsule)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func crumb(_ node: FileNode, title: String) -> some View {
        let isFocused = node === analysis.focused
        return Button {
            withAnimation(.easeOut(duration: 0.45)) { analysis.focus(node) }
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: node.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(title)
                    .fontWeight(isFocused ? .semibold : .regular)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isFocused ? theme.color.opacity(0.18) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu { NodeMenu(node: node, analysis: analysis) }
    }
}

/// The focused folder: its size, a bar split into its largest items, and the scan totals.
private struct SummaryCard: View {
    @Environment(\.theme) private var theme
    let analysis: Analysis

    var body: some View {
        let parts = analysis.focusedBreakdown.parts
        VStack(alignment: .leading, spacing: 14) {
            if analysis.unreadableCount > 0, !FullDiskAccess.isGranted {
                FullDiskAccessBanner(
                    message: "\(analysis.unreadableCount.formatted()) folders were skipped or could not be read, so their size is missing. Rescan after granting access."
                )
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    title
                    Spacer(minLength: 12)
                    StatsRow(analysis: analysis)
                }
                VStack(alignment: .leading, spacing: 12) {
                    title
                    StatsRow(analysis: analysis)
                }
            }
            SizeBar(
                parts: parts,
                height: 30,
                color: { [palette = theme.palette] part in
                    palette.color(for: part, isLit: part.node != nil && part.node === analysis.highlighted)
                },
                highlighted: analysis.highlighted,
                onHover: hover,
                onTap: open
            )
            .animation(.smooth(duration: 0.35), value: ObjectIdentifier(analysis.focused))
            Legend(parts: parts, analysis: analysis, onHover: hover, onTap: open)
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.separator.opacity(0.6)))
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(analysis.focused === analysis.root ? analysis.target.title : analysis.focused.name)
                .font(.largeTitle.weight(.bold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(analysis.focusedSize.byteString) · \(analysis.focusedSummary)")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func hover(_ part: Breakdown.Part, _ inside: Bool) {
        if inside {
            analysis.highlighted = part.node
        } else if analysis.highlighted === part.node {
            analysis.highlighted = nil
        }
    }

    /// Folders open; files are selected in the list.
    private func open(_ part: Breakdown.Part) {
        guard let node = part.node else { return }
        if node.isDirectory {
            withAnimation(.easeOut(duration: 0.35)) { analysis.focus(node) }
        } else {
            analysis.selection = [node.id]
        }
    }
}

private struct Legend: View {
    @Environment(\.theme) private var theme
    let parts: [Breakdown.Part]
    let analysis: Analysis
    let onHover: (Breakdown.Part, Bool) -> Void
    let onTap: (Breakdown.Part) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14, alignment: .leading)],
                  alignment: .leading, spacing: 8) {
            ForEach(parts) { part in
                HStack(spacing: 7) {
                    Circle()
                        .fill(theme.palette.color(for: part))
                        .frame(width: 9, height: 9)
                    Text(SizeBar.name(of: part))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(part.size.byteString)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .font(.callout)
                .opacity(analysis.highlighted == nil || part.node === analysis.highlighted ? 1 : 0.5)
                .contentShape(Rectangle())
                .onHover { onHover(part, $0) }
                .onTapGesture { onTap(part) }
                .help(SizeBar.label(for: part))
            }
        }
    }
}

private struct StatsRow: View {
    let analysis: Analysis

    var body: some View {
        HStack(spacing: 8) {
            tile("Scanned", analysis.totalSize, systemImage: "magnifyingglass")
                .help("Scanned in \(analysis.duration.formatted(.number.precision(.fractionLength(1)))) s")
            if let unaccounted = analysis.unaccountedSpace, unaccounted > 0 {
                tile("System & Other", unaccounted, systemImage: "gearshape.fill")
                    .help("Used space this scan can't see: macOS itself, APFS snapshots, other users' files, and skipped folders.")
            }
            if let volume = analysis.volume {
                tile("Free", volume.availableCapacity, systemImage: "internaldrive.fill")
                if volume.purgeableCapacity > 0 {
                    tile("Purgeable", volume.purgeableCapacity, systemImage: "arrow.3.trianglepath")
                        .help("Space macOS can reclaim automatically, such as caches and local Time Machine snapshots.")
                }
            }
        }
        .fixedSize()
    }

    private func tile(_ title: String, _ bytes: Int64, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(bytes.byteString)
                .font(.headline.monospacedDigit())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
    }
}
