import DiskCleanerCore
import SwiftUI

/// Junk categories found on this Mac with their sizes; clean the selected ones in one go.
struct QuickCleanView: View {
    @Environment(\.theme) private var theme
    @Bindable var quickClean: QuickClean
    @State private var isConfirming = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let result = quickClean.lastResult {
                    ResultBanner(result: result) { quickClean.dismissResult() }
                }
                if quickClean.available.isEmpty {
                    if quickClean.isMeasuring {
                        ProgressView("Measuring…")
                            .frame(maxWidth: .infinity)
                            .padding(40)
                    } else {
                        ContentUnavailableView("Nothing to Clean", systemImage: "sparkles",
                                               description: Text("No caches, logs or build data were found."))
                    }
                } else {
                    categoryList
                }
            }
            .padding(24)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Text("Caches, logs and build data are recreated by apps when needed.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Button { isConfirming = true } label: {
                    if quickClean.isCleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Clean \(quickClean.selectedSize.byteString)", systemImage: "sparkles")
                    }
                }
                .buttonStyle(.glassProminent)
                .tint(theme.color)
                .controlSize(.large)
                .disabled(quickClean.selectedSize == 0 || quickClean.isCleaning || quickClean.isMeasuring)
            }
            .padding(.leading, 22)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: 780)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Backdrop())
        .navigationTitle("Quick Clean")
        .navigationSubtitle(quickClean.isMeasuring ? "Measuring…" : "\(quickClean.totalSize.byteString) found")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Measure Again", systemImage: "arrow.clockwise") {
                    Task { await quickClean.measure() }
                }
                .disabled(quickClean.isMeasuring || quickClean.isCleaning)
            }
        }
        .confirmationDialog("Delete \(quickClean.selectedSize.byteString) permanently?", isPresented: $isConfirming) {
            Button("Clean", role: .destructive) { Task { await quickClean.cleanSelected() } }
        } message: {
            Text(quickClean.selected.contains("trash") && quickClean.sizes["trash"] != nil
                 ? "Apps rebuild these files when needed. Everything in the Trash is erased for good."
                 : "Apps rebuild these files when needed.")
        }
        .task { await quickClean.measure() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 30))
                .foregroundStyle(theme.color)
                .frame(width: 68, height: 68)
                .glassEffect(.regular, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Quick Clean")
                    .font(.largeTitle.weight(.bold))
                Text("Free space taken by data that apps can recreate.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(quickClean.selectedSize.byteString)
                    .font(.largeTitle.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("selected")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var categoryList: some View {
        let largest = max(quickClean.available.compactMap { quickClean.sizes[$0.id] }.max() ?? 1, 1)
        return VStack(spacing: 0) {
            ForEach(quickClean.available) { category in
                CategoryRow(
                    category: category,
                    size: quickClean.sizes[category.id] ?? 0,
                    fraction: Double(quickClean.sizes[category.id] ?? 0) / Double(largest),
                    isSelected: Binding(
                        get: { quickClean.selected.contains(category.id) },
                        set: { isOn in
                            if isOn { quickClean.selected.insert(category.id) } else { quickClean.selected.remove(category.id) }
                        }
                    )
                )
                if category != quickClean.available.last {
                    Divider().padding(.leading, 64)
                }
            }
        }
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.separator.opacity(0.6)))
    }
}

private struct CategoryRow: View {
    @Environment(\.theme) private var theme
    let category: JunkCategory
    let size: Int64
    let fraction: Double
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Toggle(category.title, isOn: $isSelected)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .tint(theme.color)
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(theme.color)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(.headline)
                Text(category.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GeometryReader { proxy in
                    Capsule()
                        .fill(theme.color.gradient)
                        .frame(width: max(3, proxy.size.width * fraction))
                }
                .frame(height: 5)
                .background(.quinary, in: Capsule())
            }
            Text(size.byteString)
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(minWidth: 90, alignment: .trailing)
            Button("Show in Finder", systemImage: "folder") { showInFinder() }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { isSelected.toggle() }
        .opacity(isSelected ? 1 : 0.6)
    }

    private var symbol: String {
        switch category.id {
        case "trash": "trash"
        case "appCaches": "shippingbox"
        case "logs": "doc.text"
        case "derivedData": "hammer"
        case "deviceSupport": "iphone"
        case "simulatorCaches": "ipad.and.iphone"
        case "homebrew": "mug"
        case "npm": "cube"
        case "gradle": "square.stack.3d.up"
        default: "folder"
        }
    }

    private func showInFinder() {
        let home = NSHomeDirectory()
        guard let folder = category.folders.map({ home + "/" + $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0) })
        else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }
}

private struct ResultBanner: View {
    @Environment(\.theme) private var theme
    let result: QuickClean.Result
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(theme.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("Freed \(result.freed.byteString)")
                    .font(.headline)
                if !result.failures.isEmpty {
                    Text("\(result.failures.count.formatted()) items were skipped because they are in use or protected.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help(result.failures.prefix(20).joined(separator: "\n"))
                }
            }
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(16)
        .background(theme.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }
}
