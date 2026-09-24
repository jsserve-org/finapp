import PhotosUI
import SwiftData
import SwiftUI

struct ScreenshotSyncSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SessionController.self) private var session
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var accountID = ScreenshotSyncService.accountID
    @State private var message = ScreenshotSyncService.lastMessage
    @State private var working = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sync = SyncController()

    var body: some View {
        Form {
            Section {
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
                Text("Choose exactly which banking screenshot to import. Ledgerly never scans or imports your photo library automatically.")
            }

            Section("Privacy") {
                Label("OCR runs entirely on this iPhone", systemImage: "iphone")
                Label("Screenshots are never uploaded", systemImage: "lock.fill")
                Label("Only the photo you select is opened", systemImage: "hand.tap.fill")
            }

            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Choose payment screenshot", systemImage: "photo.badge.plus")
                }
                .disabled(working || accountID.isEmpty)
                .onChange(of: selectedPhoto) { _, item in
                    guard let item else { return }
                    Task { await importSelected(item) }
                }
                if working { ProgressView("Reading screenshot…") }
                if let message { Text(message).foregroundStyle(.secondary) }
            } footer: {
                Text("Check the imported transaction before relying on OCR-generated details.")
            }
        }
        .navigationTitle("Screenshot Sync")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func importSelected(_ item: PhotosPickerItem) async {
        working = true
        defer { working = false; selectedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            message = ScreenshotSyncResult.unreadableImage.message
            return
        }
        let result = await ScreenshotSyncService.shared.importImageData(data, assetID: item.itemIdentifier, context: context)
        message = result.message
        if case .imported = result, session.isAuthenticated { await sync.refresh(context: context) }
    }
}
