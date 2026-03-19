import SwiftUI

/// Horizontal scrollable filter chips for protocol selection
public struct ProtocolFilterBar: View {
    @Binding var selected: String?  // nil = all
    let counts: [String: Int]       // protocol → count

    private let order = ["HTTP", "H2", "H3", "WS", "WSS", "DNS", "gRPC"]

    public init(selected: Binding<String?>, counts: [String: Int]) {
        self._selected = selected
        self.counts = counts
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" chip
                FilterChip(
                    label: "全部",
                    count: counts.values.reduce(0, +),
                    isSelected: selected == nil,
                    action: { selected = nil }
                )
                // Per-protocol chips (only show if count > 0)
                ForEach(sortedProtocols, id: \.self) { proto in
                    FilterChip(
                        label: proto,
                        count: counts[proto] ?? 0,
                        isSelected: selected == proto,
                        action: { selected = proto }
                    )
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 36)
    }

    private var sortedProtocols: [String] {
        let known = order.filter { counts[$0] != nil && counts[$0]! > 0 }
        let unknown = counts.keys.filter { !order.contains($0) }.sorted()
        return known + unknown
    }
}

struct FilterChip: View {
    let label: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                Text("(\(count))")
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .cornerRadius(14)
        }
        .buttonStyle(.plain)
    }
}
