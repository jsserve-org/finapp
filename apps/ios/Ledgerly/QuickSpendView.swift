import SwiftData
import SwiftUI

/// One-screen spending entry: type the amount, tap a category, done.
struct QuickSpendView: View {
    private static let categories = [
        "Dining", "Groceries", "Transport", "Shopping", "Bills", "Subscriptions",
        "Health", "School", "Travel", "Housing", "Other",
    ]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @AppStorage("ledgerly.quickSpend.accountID") private var lastAccountID = ""
    @AppStorage("ledgerly.quickSpend.lastCategory") private var lastCategory = "Dining"
    @State private var amount = ""
    @State private var expectsReimbursement = false
    @State private var savedMessage: String?
    @State private var showingDetails = false
    @FocusState private var amountIsFocused: Bool

    private var account: CachedAccount? {
        accounts.first { $0.id == lastAccountID }
            ?? accounts.first { $0.kind == "cash" }
            ?? accounts.first
    }

    /// The last category used comes first so a repeat lunch is the top-left tap.
    private var orderedCategories: [String] {
        [lastCategory] + Self.categories.filter { $0 != lastCategory }
    }

    var body: some View {
        if showingDetails {
            AccountEntryView(account: account, direction: .moneyOut, amount: amount)
        } else {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 18) {
                        amountField
                        Toggle("I expect reimbursement", systemImage: "arrow.uturn.backward.circle", isOn: $expectsReimbursement)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                        categoryGrid
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.never)
                .overlay { if let savedMessage { savedBanner(savedMessage) } }
                .navigationTitle("Quick spend")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("More details") { showingDetails = true }
                            .disabled(account == nil)
                    }
                }
                .sensoryFeedback(.success, trigger: savedMessage)
                .task {
                    await Task.yield()
                    amountIsFocused = true
                }
            }
        }
    }

    private var amountField: some View {
        VStack(spacing: 8) {
            TextField("0", text: $amount)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .focused($amountIsFocused)
                .minimumScaleFactor(0.55)
            Menu {
                ForEach(accounts) { option in
                    Button {
                        lastAccountID = option.id
                    } label: {
                        Label(option.name, systemImage: option.id == account?.id ? "checkmark" : AppIcon.account(kind: option.kind))
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(account.map { "\($0.name) · \($0.currency)" } ?? "No account")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.secondary)
            .accessibilityLabel("Account")
        }
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(orderedCategories, id: \.self) { category in
                Button { save(category: category) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: PaymentIcon.symbol(title: "", category: category, amountMinor: -1))
                            .font(.title3)
                        Text(category)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .tint(category == lastCategory ? .red : .secondary)
                .disabled(parsedAmount <= 0 || account == nil || savedMessage != nil)
            }
        }
    }

    private func savedBanner(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text(message).font(.headline)
            Text("Nice, that's tracked.").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save(category: String) {
        guard let account, parsedAmount > 0, savedMessage == nil else { return }
        AccountActionService.record(
            amountMinor: parsedAmount,
            description: category,
            category: category,
            date: Date(), direction: .moneyOut, account: account, context: context,
            expensePurpose: "personal",
            expectsReimbursement: expectsReimbursement
        )
        lastAccountID = account.id
        lastCategory = category
        let formatted = (Double(parsedAmount) / 100).formatted(.currency(code: account.currency).presentation(.isoCode))
        amountIsFocused = false
        withAnimation(reduceMotion ? nil : .snappy) { savedMessage = "\(formatted) · \(category)" }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            dismiss()
        }
    }
}
