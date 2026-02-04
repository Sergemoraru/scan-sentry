import SwiftUI
import SwiftData

@main
struct SafeQRApp: App {
    @State private var subscriptionManager = SubscriptionManager()
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(subscriptionManager)
        }
        .modelContainer(for: [ScanRecord.self, DocumentRecord.self])
    }
}
