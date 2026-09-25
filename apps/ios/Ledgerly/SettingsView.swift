import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionController.self) private var session
    @State private var healthState: String?
    @State private var isChecking = false
    @State private var demoMessage: String?
    @State private var backupDocument: LedgerlyBackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var backupMessage: String?
    @State private var compatibility: LedgerlyCompatibility?
    @State private var serverVersion: String?

    var body: some View {
        Form {
                Section("Sync") {
                    if session.localOnly {
                        Label("On this iPhone", systemImage: "iphone")
                        Button("Set up sync") { session.configureSync() }
                    } else {
                        LabeledContent("Account", value: UserDefaults.standard.string(forKey: "ledgerly.username") ?? "—")
                        NavigationLink {
                            ServerSettingsView()
                        } label: {
                            Label("Server", systemImage: "server.rack")
                        }
                        NavigationLink {
                            APIKeysView()
                        } label: {
                            Label("API keys", systemImage: "key.fill")
                        }
                        NavigationLink { ConnectionHealthView() } label: { Label("Server status", systemImage: "network") }
                        LabeledContent("Status", value: healthState ?? "—")
                        LabeledContent("App version", value: LedgerlyCompatibility.appVersion)
                        LabeledContent("Server version", value: serverVersion ?? "—")
                        if let compatibility {
                            Label(compatibility.message, systemImage: compatibility.canSync ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(compatibility.canSync ? Color.secondary : Color.red)
                        }
                        Button { Task { await check() } } label: {
                            if isChecking { ProgressView() } else { Label("Check connection", systemImage: "stethoscope") }
                        }
                    }
                }
                Section("About") {
                    LabeledContent("App", value: "Ledgerly")
                    LabeledContent("Sync", value: "Cursor-based /v1/sync")
                }
                Section("Privacy") {
                    NavigationLink { AppPrivacySettingsView() } label: {
                        Label("App lock & screenshots", systemImage: "lock.shield.fill")
                    }
                    Text("Hide financial information outside the active app, configure PIN or biometrics, and control screenshot notices.")
                        .foregroundStyle(.secondary)
                }
                Section("Backup") {
                    Button("Export backup", systemImage: "square.and.arrow.up") { exportBackup() }
                    Button("Import backup", systemImage: "square.and.arrow.down") { showingImporter = true }
                }
                Section("Automation") {
                    NavigationLink {
                        ScreenshotSyncSettingsView()
                    } label: {
                        Label("Screenshot Sync", systemImage: "photo.on.rectangle")
                    }
                    Text("Import a payment screenshot into the account you choose.")
                        .foregroundStyle(.secondary)
                }
                #if DEBUG
                Section("Demo") {
                    Button("Load sample data", systemImage: "sparkles") { loadDemo() }
                    Text("Adds sample TWD accounts, transactions, and recurring payments when the app is empty.")
                        .foregroundStyle(.secondary)
                }
                #endif
                if !session.localOnly { Section { Button("Log out", role: .destructive) { session.logout() } } }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .alert("Demo", isPresented: Binding(
            get: { demoMessage != nil },
            set: { if !$0 { demoMessage = nil } }
        )) {
            Button("OK") { demoMessage = nil }
        } message: {
            Text(demoMessage ?? "")
        }
        .alert("Backup", isPresented: Binding(
            get: { backupMessage != nil },
            set: { if !$0 { backupMessage = nil } }
        )) {
            Button("OK") { backupMessage = nil }
        } message: {
            Text(backupMessage ?? "")
        }
        .fileExporter(isPresented: $showingExporter, document: backupDocument, contentType: .json, defaultFilename: "Ledgerly Backup") { result in
            if case .failure(let error) = result { backupMessage = error.localizedDescription }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importBackup(result)
        }
        .task { await checkVersions() }
    }

    private func check() async {
        isChecking = true
        defer { isChecking = false }
        do {
            try await APIClient.shared.healthReady()
            healthState = "ready"
            await checkVersions()
        } catch {
            healthState = "unreachable"
        }
    }

    private func checkVersions() async {
        guard !session.localOnly, let config = try? await APIClient.shared.serverConfig() else { return }
        serverVersion = config.serverVersion
        compatibility = LedgerlyCompatibility.evaluate(config)
    }

    private func exportBackup() {
        do {
            backupDocument = LedgerlyBackupDocument(backup: try LedgerlyBackupService.create(from: context))
            showingExporter = true
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func importBackup(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            let backup = try LedgerlyBackupService.decoder.decode(LedgerlyBackup.self, from: data)
            let count = try LedgerlyBackupService.restore(backup, into: context)
            backupMessage = "Imported \(count) item\(count == 1 ? "" : "s")."
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    #if DEBUG
    private func loadDemo() {
        do {
            demoMessage = try DemoData.load(into: context)
                ? "Sample data is ready."
                : "Sample data can only be loaded when there are no accounts."
        } catch {
            demoMessage = "Could not load sample data."
        }
    }
    #endif
}

private struct ServerSettingsView: View {
    @State private var apiURL = AppConfig.baseURL.absoluteString
    @State private var convexURL = AppConfig.convexURL.absoluteString
    @State private var isTesting = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("API endpoint", text: $apiURL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                TextField("Convex endpoint", text: $convexURL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            } header: {
                Text("Endpoints")
            } footer: {
                Text("The app syncs through the API. The Convex address identifies your self-hosted deployment during login.")
            }

            Section {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    if isTesting { ProgressView() } else { Label("Save and test", systemImage: "checkmark.circle") }
                }
                .disabled(isTesting)

                if let message {
                    Text(message)
                        .foregroundStyle(message == "Connection ready" ? .green : .red)
                }
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveAndTest() async {
        let trimmedAPI = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConvex = convexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api = URL(string: trimmedAPI),
              let convex = URL(string: trimmedConvex),
              let apiScheme = api.scheme?.lowercased(),
              let convexScheme = convex.scheme?.lowercased(),
              ["http", "https"].contains(apiScheme),
              ["http", "https"].contains(convexScheme),
              api.host != nil, convex.host != nil else {
            message = "Enter valid HTTP(S) endpoint URLs."
            return
        }

        isTesting = true
        message = nil
        UserDefaults.standard.set(api.absoluteString, forKey: "ledgerly.apiURL")
        UserDefaults.standard.set(convex.absoluteString, forKey: "ledgerly.convexURL")
        apiURL = api.absoluteString
        convexURL = convex.absoluteString

        do {
            try await APIClient.shared.healthReady()
            message = "Connection ready"
        } catch {
            message = "Saved, but the API is unreachable."
        }
        isTesting = false
    }
}
