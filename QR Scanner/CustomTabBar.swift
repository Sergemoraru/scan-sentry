import SwiftUI

enum AppTab: Hashable {
    case scan
    case history
    case settings

    var title: String {
        switch self {
        case .scan: return "Scan"
        case .history: return "History"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .scan: return "qrcode.viewfinder"
        case .history: return "clock"
        case .settings: return "gear"
        }
    }
}

struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 10) {
            tabButton(.scan)
            Spacer(minLength: 0)
            tabButton(.history)
            Spacer(minLength: 0)
            tabButton(.settings)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 6) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                Text(tab.title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selection == tab ? Color.accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }
}
