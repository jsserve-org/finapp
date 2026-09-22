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

    var body: some View {
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
                Section("Backup") {
                    Button("Export backup", systemImage: "square.and.arrow.up") { exportBackup() }
                    Button("Import backup", systemImage: "square.and.arrow.down") { showingImporter = true }
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
