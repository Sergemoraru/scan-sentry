import SwiftUI

private struct TabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 90
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct RootView: View {
    // Distance from the *physical* bottom edge.
    private let tabBarBottomInset: CGFloat = 0

    @State private var tab: AppTab = .scan
    @State private var tabBarHeight: CGFloat = 90

    private var bottomReserved: CGFloat { tabBarBottomInset + tabBarHeight }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let safe = proxy.safeAreaInsets

            ZStack {
                Group {
                    switch tab {
                    case .scan:
                        ScanView(bottomReserved: bottomReserved)
                    case .history:
                        HistoryView()
                            .safeAreaInset(edge: .bottom) {
                                Color.clear.frame(height: bottomReserved)
                            }
                    case .settings:
                        SettingsView()
                            .safeAreaInset(edge: .bottom) {
                                Color.clear.frame(height: bottomReserved)
                            }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                CustomTabBar(selection: $tab)
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .preference(key: TabBarHeightKey.self, value: g.size.height)
                        }
                    )
                    .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight = $0 }
                    // Absolutely position at the physical bottom edge.
                    .position(
                        x: size.width / 2,
                        y: (size.height + safe.bottom) - tabBarBottomInset - (tabBarHeight / 2)
                    ) // include unsafe-area height so we can reach the physical bottom
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .ignoresSafeArea()
        }
    }
}
