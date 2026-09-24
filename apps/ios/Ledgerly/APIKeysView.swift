import SwiftUI
import UIKit

struct APIKeysView: View {
    @State private var keys: [APIKeySummary] = []
    @State private var name = ""
    @State private var createdKey: CreatedAPIKey?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                TextField("Key name", text: $name)
                Button {
                    Task { await create() }
                } label: {
                    if isLoading { ProgressView() } else { Label("Create API key", systemImage: "plus.circle.fill") }
                }
                .disabled(isLoading || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Use a separate named key for each AI agent or automation. The full secret is shown only once.")
            }

            Section("Active keys") {
                ForEach(keys) { key in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key.name).font(.headline)
                        Text("\(key.prefix)… · Created \(createdDate(key.createdAt))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Revoke", systemImage: "trash", role: .destructive) {
                            Task { await revoke(key) }
                        }
                    }
                }
                if keys.isEmpty, !isLoading {
                    ContentUnavailableView("No API keys", systemImage: "key.fill", description: Text("Create one for your AI agent or personal automation."))
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("API Keys")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(item: $createdKey) { key in
            NavigationStack {
                Form {
                    Section("Copy this key now") {
                        Text(key.key)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        Button("Copy API key", systemImage: "doc.on.doc.fill") {
                            UIPasteboard.general.string = key.key
                        }
                    }
                    Section {
                        Label("This secret cannot be displayed again.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .navigationTitle(key.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { createdKey = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { keys = try await APIClient.shared.apiKeys(); errorMessage = nil }
        catch { errorMessage = "Could not load API keys." }
    }

    private func create() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let key = try await APIClient.shared.createAPIKey(name: trimmed)
            createdKey = key
            name = ""
            keys = try await APIClient.shared.apiKeys()
            errorMessage = nil
        } catch { errorMessage = "Could not create the API key." }
    }

    private func revoke(_ key: APIKeySummary) async {
        do {
            try await APIClient.shared.revokeAPIKey(id: key.id)
            keys.removeAll { $0.id == key.id }
            errorMessage = nil
        } catch { errorMessage = "Could not revoke the API key." }
    }

    private func createdDate(_ milliseconds: Double) -> String {
        Date(timeIntervalSince1970: milliseconds / 1_000).formatted(date: .abbreviated, time: .omitted)
    }
}
