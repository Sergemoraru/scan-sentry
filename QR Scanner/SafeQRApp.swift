import SwiftUI
import SwiftData

@main
struct SafeQRApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [ScanRecord.self, DocumentRecord.self])
    }
}
