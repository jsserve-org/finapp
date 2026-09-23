import Photos
import SwiftData
import SwiftUI

struct ScreenshotSyncSettingsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var enabled = ScreenshotSyncService.isEnabled
    @State private var accountID = ScreenshotSyncService.accountID
    @State private var message = ScreenshotSyncService.lastMessage
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Toggle("Automatic import", isOn: $enabled)
                    .onChange(of: enabled) { _, value in Task { await updateEnabled(value) } }
                Picker("Save payments to", selection: $accountID) {
                    Text("Choose an account").tag("")
                    ForEach(accounts) { account in
                        Text("\(account.name) · \(account.currency)").tag(account.id)
                    }
                }
                .onChange(of: accountID) { _, value in
                    UserDefaults.standard.set(value, forKey: ScreenshotSyncService.accountIDKey)
                }
            } header: {
                Text("Screenshot Sync")
            } footer: {
                Text("Take a payment screenshot in your banking app, then return to Ledgerly. The newest screenshot is read on this iPhone and imported once.")
            }

            Section("Privacy") {
                Label("OCR runs entirely on this iPhone", systemImage: "iphone")
                Label("Screenshots are never uploaded", systemImage: "lock.fill")
                Label("Full Photos access is required", systemImage: "photo.stack")
            }

            Section {
                Button { Task { await importNow() } } label: {
                    if working { ProgressView() }
                    else { Label("Import latest screenshot", systemImage: "photo.badge.checkmark") }
                }
                .disabled(working || accountID.isEmpty)
                if let message { Text(message).foregroundStyle(.secondary) }
            } footer: {
                Text("Use this button to retry the newest screenshot. Check the imported transaction before relying on OCR-generated details.")
            }
        }
        .navigationTitle("Screenshot Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updateEnabled(_ value: Bool) async {
        if value, accountID.isEmpty, let first = accounts.first {
            accountID = first.id
            UserDefaults.standard.set(first.id, forKey: ScreenshotSyncService.accountIDKey)
        }
        let actual = await ScreenshotSyncService.shared.setEnabled(value)
        enabled = actual
        if value, !actual { message = ScreenshotSyncResult.permissionDenied.message }
    }

    private func importNow() async {
        working = true
        let result = await ScreenshotSyncService.shared.importLatest(context: context, force: true)
        message = result.message
        working = false
    }
}
