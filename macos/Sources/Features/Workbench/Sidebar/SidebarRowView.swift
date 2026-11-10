import SwiftUI

/// One sidebar row: color dot, title, cwd · branch ●, badge and goal progress (constraint 8).
struct SidebarRowView: View {
    let row: SidebarRow

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(Color(nsColor: ColorAllocator.nsColor(row.color)))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title.isEmpty ? row.cwdName : row.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(secondary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 2)
            BadgeView(badge: row.badge)
            if let progress = row.progress {
                Text(progress)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var secondary: String {
        var parts = [row.cwdName]
        if !row.gitLabel.isEmpty { parts.append(row.gitLabel) }
        if row.dirty { parts.append("●") }
        return parts.joined(separator: " ")
    }
}

/// The status badge (constraint 12).
struct BadgeView: View {
    let badge: Badge

    var body: some View {
        switch badge {
        case .none:
            EmptyView()
        case .spinner:
            ProgressView().controlSize(.mini)
        case .hollow:
            Image(systemName: "circle").font(.caption2).foregroundStyle(.secondary)
        case .attention:
            Image(systemName: "exclamationmark").font(.caption.bold()).foregroundStyle(.orange)
        case .done:
            Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
        }
    }
}
