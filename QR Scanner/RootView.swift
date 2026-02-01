import SwiftUI

private struct TabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 90
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RootView: View {
    // User preference: keep the menu very close to the bottom.
    private let tabBarBottomOffset: CGFloat = 0

    @State private var tab: AppTab = .scan
    @State private var tabBarHeight: CGFloat = 90

    private var bottomReserved: CGFloat { tabBarBottomOffset + tabBarHeight }

    var body: some View {
        ZStack {
            Group {
                switch tab {
                case .scan:
                    ScanView(bottomReserved: bottomReserved)
                case .history:
                    HistoryView()
                        .padding(.bottom, bottomReserved)
                case .settings:
                    SettingsView()
                        .padding(.bottom, bottomReserved)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer(minLength: 0)
                CustomTabBar(selection: $tab)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(key: TabBarHeightKey.self, value: g.size.height)
                        }
                    )
                    .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight = $0 }
                    .padding(.bottom, tabBarBottomOffset)
            }
            // Let the bar float closer to the physical bottom edge.
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
