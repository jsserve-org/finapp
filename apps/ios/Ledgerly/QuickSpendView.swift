import SwiftData
import SwiftUI

/// Two-page spending entry: enter the amount, then tap a category to save.
struct QuickSpendView: View {
    private enum Step: Int {
        case amount
        case category

        var title: String {
            switch self {
            case .amount: "Enter amount"
            case .category: "Choose category"
            }
        }
    }

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
    @State private var currency = SupportedCurrency.defaultCode
    @State private var expectsReimbursement = false
    @State private var step: Step = .amount
    @State private var movesForward = true
    @State private var showingDetails = false

    private var account: CachedAccount? {
        accounts.first { $0.id == lastAccountID }
            ?? accounts.first { $0.kind == "cash" }
            ?? accounts.first
    }

    /// The last category used comes first so a repeat lunch is the top row.
    private var orderedCategories: [String] {
        [lastCategory] + Self.categories.filter { $0 != lastCategory }
    }

    var body: some View {
        if showingDetails {
            AccountEntryView(account: account, direction: .moneyOut, amount: amount)
        } else {
            NavigationStack {
                ZStack {
                    switch step {
                    case .amount: amountStep
                    case .category: categoryStep
                    }
                }
                .id(step)
                .transition(stepTransition)
                .navigationTitle(step.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if step == .amount {
                            Button("Cancel") { dismiss() }
                        } else {
                            Button("Back", systemImage: "chevron.left") { goBack() }
                        }
                    }
                    if step != .amount {
                        ToolbarItem(placement: .confirmationAction) { Button("Cancel") { dismiss() } }
                    }
                }
                .task {
                    guard let account else { return }
                    lastAccountID = account.id
                    currency = account.currency
                }
            }
        }
    }

    private var amountStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 1, total: 2, instruction: "How much did you spend?")
                MoneyAmountHeader(title: "Purchase amount", amount: $amount, currency: $currency, tint: .red, currencyLocked: true)
            }
            .listRowBackground(Color.clear)
            Section("Paid with") {
                Picker("Account", selection: $lastAccountID) {
                    ForEach(accounts) { option in
                        Text(option.name).tag(option.id)
                    }
                }
                .onChange(of: lastAccountID) { if let account { currency = account.currency } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Choose category", systemImage: "arrow.right", tint: .red, disabled: parsedAmount <= 0 || account == nil) {
                goForward(to: .category)
            }
        }
    }

    private var categoryStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 2, total: 2, instruction: "Tap a category to save")
            }
            .listRowBackground(Color.clear)
            Section {
                Toggle("I expect reimbursement", isOn: $expectsReimbursement)
            }
            Section("Category") {
                ForEach(orderedCategories, id: \.self) { category in
                    Button { save(category: category) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: PaymentIcon.symbol(title: "", category: category, amountMinor: -1)).ledgerlyIcon(color: .red)
                            Text(category).font(.headline).foregroundStyle(.primary)
                            Spacer()
                            if category == lastCategory {
                                Text("Last used").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                Button("Add more details", systemImage: "square.and.pencil") { showingDetails = true }
            }
        }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        movesForward = false
        withAnimation(stepAnimation) { step = previous }
    }

    private func goForward(to next: Step) {
        movesForward = true
        withAnimation(stepAnimation) { step = next }
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.38, extraBounce: 0.04)
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movesForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movesForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save(category: String) {
        guard let account, parsedAmount > 0 else { return }
        AccountActionService.record(
            amountMinor: parsedAmount,
            description: category,
            category: category,
            date: Date(), direction: .moneyOut, account: account, context: context,
            expensePurpose: "personal",
            expectsReimbursement: expectsReimbursement
        )
        lastCategory = category
        dismiss()
    }
}
