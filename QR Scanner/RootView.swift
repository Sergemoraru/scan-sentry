import SwiftUI
import UIKit

struct RootView: View {
    init() {
        // Force the iOS tab bar to be transparent / minimally translucent so the camera shows behind it.
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        // Use a dark material instead of nil to avoid iOS drawing an opaque/white fallback.
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = .clear

        // Remove the default shadow line.
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().isTranslucent = true
    }

    @AppStorage("hasShownOnboarding") private var hasShownOnboarding: Bool = false
    @State private var showOnboarding = false

    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("Scan", systemImage: "qrcode.viewfinder") }

            DocumentsListView()
                .tabItem { Label("Documents", systemImage: "doc.text.viewfinder") }

            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        // SwiftUI-level hint to hide tab bar background.
        .toolbarBackground(.hidden, for: .tabBar)
        .sheet(isPresented: $showOnboarding, onDismiss: {
            hasShownOnboarding = true
        }) {
            OnboardingView(isPresented: $showOnboarding)
                .interactiveDismissDisabled()
        }
        .onAppear {
            if !hasShownOnboarding {
                showOnboarding = true
            }
        }
    }
}

