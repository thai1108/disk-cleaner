import DiskCleanerCore
import SwiftUI

/// A horizontal bar split into a folder's largest items, like the Storage page of System Settings.
struct SizeBar: View {
    let parts: [Breakdown.Part]
    /// Share of the width the parts fill; the rest is empty track.
    var filled: Double = 1
    var height: CGFloat
    var spacing: CGFloat = 2
    let color: (Breakdown.Part) -> Color
    /// Dims every other part while one item is highlighted.
    var highlighted: FileNode?
    var onHover: ((Breakdown.Part, Bool) -> Void)?
    var onTap: ((Breakdown.Part) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let gaps = spacing * Double(max(0, parts.count - 1))
            let width = max(0, proxy.size.width * filled - gaps)
            HStack(spacing: spacing) {
                ForEach(parts) { part in
                    segment(part)
                        .frame(width: max(1, width * part.fraction))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.32))
    }

    @ViewBuilder
    private func segment(_ part: Breakdown.Part) -> some View {
        let base = Rectangle()
            .fill(color(part).gradient)
            .opacity(highlighted == nil || part.node === highlighted ? 1 : 0.4)
            .contentShape(Rectangle())
            .help(Self.label(for: part))
        if onHover != nil || onTap != nil {
            base
                .onHover { onHover?(part, $0) }
                .onTapGesture { onTap?(part) }
        } else {
            base
        }
    }

    static func name(of part: Breakdown.Part) -> String {
        switch part.content {
        case .node(let node): node.name
        case .otherItems(let count): count == 1 ? "1 smaller item" : "\(count.formatted()) smaller items"
        }
    }

    static func label(for part: Breakdown.Part) -> String {
        let share = part.fraction.formatted(.percent.precision(.fractionLength(1)))
        return "\(name(of: part)) — \(part.size.byteString) (\(share))"
    }
}
