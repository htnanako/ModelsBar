import SwiftUI

extension KeyStatus {
    var tint: Color {
        switch self {
        case .unknown: .secondary
        case .healthy: .green
        case .warning: .yellow
        case .failed: .red
        case .disabled: .gray
        }
    }
}

struct StatusBadge: View {
    var status: KeyStatus
    var title: String?

    var body: some View {
        Label(title ?? status.title, systemImage: status.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(status.tint.opacity(0.12), in: Capsule())
    }
}

struct EmptyHintView: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

extension Date {
    var shortDisplay: String {
        formatted(date: .abbreviated, time: .shortened)
    }
}
