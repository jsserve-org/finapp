import SwiftUI

struct ConnectionHealthView: View {
    @State private var statuses: [ConnectionStatus] = []
    @State private var isLoading = false
    @State private var isRunningDemo = false
    @State private var errorText: String?

    var body: some View {
        List {
            if let errorText {
                Section { Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            Section("Connections") {
                ForEach(statuses, id: \.connectionId) { status in
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent {
                            Text(status.connectionId.prefix(8) + "…").foregroundStyle(.secondary)
                        } label: {
                            Label(status.state.capitalized, systemImage: status.state == "healthy" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(status.state == "healthy" ? .green : .orange)
                        }
                        if let lastError = status.lastError { Text(lastError).font(.subheadline).foregroundStyle(.orange) }
                        if let lastSuccess = status.lastSuccessAt, let date = ISO8601DateFormatter().date(from: lastSuccess) {
                            LabeledContent("Last success", value: date.formatted(.relative(presentation: .named)))
                        }
                        if let next = ISO8601DateFormatter().date(from: status.nextCheckAt) {
                            LabeledContent("Next check", value: next.formatted(.relative(presentation: .named)))
                        }
                    }
                }
                if statuses.isEmpty && !isLoading && errorText == nil {
                    ContentUnavailableView("No connections", systemImage: "antenna.radiowaves.left.and.right", description: Text("Connect a bank when you are ready."))
                }
            }
            Section {
                Button {
                    Task { await runDemo() }
                } label: {
                    if isRunningDemo { ProgressView() }
                    else { Label("Run demo import", systemImage: "sparkles") }
                }
            }
        }
        .navigationTitle("Connections")
        .toolbar { if isLoading { ProgressView() } }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do { statuses = try await APIClient.shared.connectionStatuses(); errorText = nil }
        catch { errorText = "Could not reach the API." }
    }

    private func runDemo() async {
        isRunningDemo = true
        defer { isRunningDemo = false }
        do { try await APIClient.shared.runDemoAutomation(); await load() }
        catch { errorText = "Demo import failed." }
    }
}
