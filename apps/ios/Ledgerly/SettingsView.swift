import SwiftUI

struct SettingsView: View {
    @AppStorage("ledgerly.useCustomToken") private var useCustomToken = false
    @State private var customToken = ""
    @State private var healthState: String?
    @State private var isChecking = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            Form {
                Section("API") {
                    LabeledContent("Base URL", value: AppConfig.baseURL.absoluteString)
                    LabeledContent("Token source", value: useCustomToken ? "Keychain" : "Build config")
                    Toggle("Use Keychain token", isOn: $useCustomToken)
                    if useCustomToken {
                        SecureField("Bearer token", text: $customToken)
                        Button("Save token to Keychain") {
                            KeychainStore().saveToken(customToken)
                        }.disabled(customToken.isEmpty)
                        Button("Remove saved token", role: .destructive) {
                            KeychainStore().deleteToken()
                        }
                    }
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
