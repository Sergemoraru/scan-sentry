import SwiftUI

struct RootView: View {
    // User preference: keep the menu very close to the bottom.
    private let tabBarBottomOffset: CGFloat = 30
    private let tabBarHeight: CGFloat = 70

    @State private var tab: AppTab = .scan

    var body: some View {
        ZStack {
            Group {
                switch tab {
                case .scan:
                    ScanView(bottomReserved: tabBarBottomOffset + tabBarHeight)
                case .history:
                    HistoryView()
                        .padding(.bottom, tabBarBottomOffset + tabBarHeight)
                case .settings:
                    SettingsView()
                        .padding(.bottom, tabBarBottomOffset + tabBarHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack {
                Spacer(minLength: 0)
                CustomTabBar(selection: $tab)
                    .frame(height: tabBarHeight)
                    .padding(.bottom, tabBarBottomOffset)
            }
            // Let the bar float closer to the physical bottom edge.
            .ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
