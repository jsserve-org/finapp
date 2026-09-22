import SwiftData
import SwiftUI

@main
struct LedgerlyApp: App {
    var body: some Scene {
        WindowGroup { DashboardView() }
            .modelContainer(for: [CachedAccount.self, CachedTransaction.self, SyncSetting.self])
    }
}
