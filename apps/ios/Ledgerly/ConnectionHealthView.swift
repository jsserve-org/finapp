import SwiftUI

struct ConnectionHealthView: View {
    @State private var statuses: [ConnectionStatus] = []
    @State private var isLoading = false
    @State private var isRunningDemo = false
    @State private var errorText: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.02, green: 0.12, blue: 0.09), Color(red: 0.03, green: 0.22, blue: 0.16)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).padding(12).ledgerlyGlass(cornerRadius: 14)
                    }
                    ForEach(statuses, id: \.connectionId) { status in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Circle().fill(status.state == "healthy" ? .green : .orange).frame(width: 10, height: 10)
                                Text(status.state.capitalized).font(.headline)
                                Spacer()
                                Text(status.connectionId.prefix(8) + "…").font(.caption2).foregroundStyle(.tertiary)
                            }
                            if let lastError = status.lastError {
                                Text(lastError).font(.caption).foregroundStyle(.orange)
                            }
                            if let lastSuccess = status.lastSuccessAt, let date = ISO8601DateFormatter().date(from: lastSuccess) {
                                Text("Last success: \(date.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                            }
                            if let next = ISO8601DateFormatter().date(from: status.nextCheckAt) {
                                Text("Next check: \(next.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).ledgerlyGlass(cornerRadius: 20)
                    }
                    if statuses.isEmpty && !isLoading && errorText == nil {
                        ContentUnavailableView("No connections", systemImage: "antenna.radiowaves.left.and.right", description: Text("Run the demo automation to create one."))
                    }
                }.padding(20)
            }
        }
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isLoading { ProgressView() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await runDemo() }
            } label: {
                if isRunningDemo { ProgressView().frame(maxWidth: .infinity) }
                else { Label("Run demo import", systemImage: "sparkles").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent).tint(.mint).padding()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            statuses = try await APIClient.shared.connectionStatuses()
            errorText = nil
        } catch {
            errorText = "Could not reach the API."
        }
    }

    private func runDemo() async {
        isRunningDemo = true
        defer { isRunningDemo = false }
        do {
            try await APIClient.shared.runDemoAutomation()
            await load()
        } catch {
            errorText = "Demo import failed."
        }
    }
}
