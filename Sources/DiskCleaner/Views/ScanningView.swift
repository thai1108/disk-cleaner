import DiskCleanerCore
import SwiftUI

struct ScanningView: View {
    @Environment(AppModel.self) private var model
    let session: ScanSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { context in
            let progress = session.progress
            VStack(spacing: 28) {
                ZStack {
                    ProgressRing(fraction: session.estimatedFraction)
                    VStack(spacing: 4) {
                        Text(progress.bytesScanned.byteString)
                            .font(.largeTitle.weight(.semibold).monospacedDigit())
                            .contentTransition(.numericText())
                        Text(elapsed(at: context.date))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 230, height: 230)

                VStack(spacing: 8) {
                    Text("Scanning \(session.target.title)…")
                        .font(.title2.weight(.semibold))
                    Text("\(progress.filesScanned.formatted()) files in \(progress.directoriesScanned.formatted()) folders")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(PathRules.friendlyPath(progress.currentPath))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: 520)
                        .glassEffect(.regular, in: .capsule)
                        .padding(.top, 6)
                }

                Button("Cancel", role: .cancel) { model.cancelScan() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Backdrop())
        .navigationTitle(session.target.title)
        .navigationSubtitle("Scanning…")
    }

    private func elapsed(at date: Date) -> String {
        let seconds = Int(date.timeIntervalSince(session.startedAt))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Determinate ring when the total is known, otherwise a spinning arc.
private struct ProgressRing: View {
    @Environment(\.theme) private var theme
    let fraction: Double?
    @State private var isSpinning = false
    private let lineWidth: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quinary, lineWidth: lineWidth)
            if let fraction {
                arc(to: fraction)
                    .animation(.easeOut(duration: 0.3), value: fraction)
            } else {
                arc(to: 0.28)
                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: isSpinning)
                    .onAppear { isSpinning = true }
            }
        }
        .shadow(color: theme.color.opacity(0.3), radius: 14)
    }

    private func arc(to end: Double) -> some View {
        Circle()
            .trim(from: 0, to: end)
            .stroke(
                AngularGradient(colors: [theme.color.opacity(0.3), theme.color],
                                center: .center, startAngle: .zero, endAngle: .degrees(360 * end)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
    }
}
