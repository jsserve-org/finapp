import SwiftUI

struct SettingsView: View {
    @Environment(SessionController.self) private var session
    @State private var healthState: String?
    @State private var isChecking = false

    var body: some View {
        ZStack {
            LedgerlyBackground()
            Form {
                Section("Sync") {
                    if session.localOnly {
                        Label("On this iPhone", systemImage: "iphone")
                        Button("Set up sync") { session.configureSync() }
                    } else {
                        LabeledContent("Account", value: UserDefaults.standard.string(forKey: "ledgerly.username") ?? "—")
                        NavigationLink { ConnectionHealthView() } label: { Label("Server status", systemImage: "network") }
                        LabeledContent("Status", value: healthState ?? "—")
                        Button { Task { await check() } } label: {
                            if isChecking { ProgressView() } else { Label("Check connection", systemImage: "stethoscope") }
                        }
                    }
                }
                Section("About") {
                    LabeledContent("App", value: "Ledgerly")
                    LabeledContent("Sync", value: "Cursor-based /v1/sync")
                }
                if !session.localOnly { Section { Button("Log out", role: .destructive) { session.logout() } } }
            }.scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .preferredColorScheme(.dark)
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        do {
            try await APIClient.shared.healthReady()
            healthState = "ready"
        } catch {
            healthState = "unreachable"
        }
    }
}
