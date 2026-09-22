import SwiftUI

struct SettingsView: View {
    @Environment(SessionController.self) private var session
    @State private var healthState: String?
    @State private var isChecking = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            Form {
                Section("API") {
                    LabeledContent("Base URL", value: AppConfig.baseURL.absoluteString)
                    LabeledContent("Convex URL", value: AppConfig.convexURL.absoluteString)
                    LabeledContent("Username", value: UserDefaults.standard.string(forKey: "ledgerly.username") ?? "—")
                }
                Section("Health") {
                    LabeledContent("Status", value: healthState ?? "—")
                    Button {
                        Task { await check() }
                    } label: {
                        if isChecking { ProgressView() } else { Label("Check API health", systemImage: "stethoscope") }
                    }
                }
                Section("About") {
                    LabeledContent("App", value: "Ledgerly")
                    LabeledContent("Sync", value: "Cursor-based /v1/sync")
                }
                Section { Button("Log out", role: .destructive) { session.logout() } }
            }.scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
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
