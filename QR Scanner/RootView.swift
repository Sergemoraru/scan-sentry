import SwiftUI
import UIKit

struct RootView: View {
    init() {
        // Force the iOS tab bar to be transparent so the camera shows behind it.
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("Scan", systemImage: "qrcode.viewfinder") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        // SwiftUI-level hint to hide tab bar background.
        .toolbarBackground(.hidden, for: .tabBar)
    }
}
