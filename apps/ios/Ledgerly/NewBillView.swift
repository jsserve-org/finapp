import SwiftData
import SwiftUI

struct NewBillView: View {
    private enum Step: Int {
        case account
        case amount
        case details

        var title: String {
            switch self {
            case .account: "Choose account"
            case .amount: "Enter amount"
            case .details: "Additional information"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var name = ""
    @State private var amount = ""
    @State private var settlementAmount = ""
    @State private var currency = SupportedCurrency.defaultCode
    @State private var category = "Bills"
    @State private var paymentDate = Date()
    @State private var accountId = ""
    @State private var expensePurpose = "personal"
    @State private var reimbursable = false
    @State private var step: Step = .account
    @State private var movesForward = true

    private var selectedAccount: CachedAccount? { accounts.first { $0.id == accountId } }
    private var needsSettlementAmount: Bool { selectedAccount.map { $0.currency != currency } ?? false }

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .account: accountStep
                case .amount: amountStep
                case .details: detailsStep
                }
            }
            .id(step)
            .transition(stepTransition)
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if step == .account {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Back", systemImage: "chevron.left") { goBack() }
                    }
                }
                if step != .account {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task { selectDefaultAccount() }
            .onChange(of: expensePurpose) { _, purpose in
                if purpose == "school", category == "Bills" { category = "School" }
            }
            .onChange(of: accountId) { _, id in
                if accounts.first(where: { $0.id == id })?.kind == "sharedCredit" {
                    expensePurpose = "someoneElse"
                }
            }
        }
    }

    private var accountStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 1, total: 3, instruction: "Which account will pay this bill?")
            }
            .listRowBackground(Color.clear)
            Section("Pay from") {
                ForEach(accounts) { account in
                    Button {
                        accountId = account.id
                        if amount.isEmpty { currency = account.currency }
                    } label: {
                        accountRow(account, selected: account.id == accountId)
                    }
                    .buttonStyle(.plain)
                }
                if accounts.isEmpty {
                    ContentUnavailableView("Create an account first", systemImage: "building.columns", description: Text("A one-time bill needs an account to pay from."))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Enter amount", systemImage: "arrow.right", tint: .red, disabled: selectedAccount == nil) {
                goForward(to: .amount)
            }
        }
    }

    private var amountStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 2, total: 3, instruction: selectedAccount?.name ?? "Purchase amount")
                MoneyAmountHeader(title: "Purchase amount", amount: $amount, currency: $currency, tint: .red)
            }
            .listRowBackground(Color.clear)
            if let account = selectedAccount, needsSettlementAmount {
                Section {
                    TextField("Amount charged in \(account.currency)", text: $settlementAmount)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("Bank charge")
                } footer: {
                    Text("Enter the amount your bank charged after currency conversion.")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Additional information", systemImage: "arrow.right", tint: .red, disabled: parsedAmount <= 0 || (needsSettlementAmount && parsedSettlementAmount <= 0)) {
                goForward(to: .details)
            }
        }
    }

    private var detailsStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 3, total: 3, instruction: "Review and save")
            }
            .listRowBackground(Color.clear)
            Section("Summary") {
                LabeledContent("Account", value: selectedAccount?.name ?? "")
                LabeledContent("Amount", value: money(parsedAmount, currency))
            }
            Section("Bill") {
                TextField("Name", text: $name)
                TransactionCategoryPicker(selection: $category)
                DatePicker("Payment date", selection: $paymentDate, displayedComponents: .date)
            }
            Section("For") {
                Picker("Purpose", selection: $expensePurpose) {
                    Text("Personal").tag("personal")
                    Text("School").tag("school")
                    Text("Someone else").tag("someoneElse")
                }
                Toggle("I expect reimbursement", isOn: $reimbursable)
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Add one-time bill", systemImage: "doc.badge.plus", tint: .red, disabled: !canSave, action: save)
        }
    }

    private func accountRow(_ account: CachedAccount, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: AppIcon.account(kind: account.kind)).ledgerlyIcon()
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.headline).foregroundStyle(.primary)
                Text("\(account.institution) · \(money(account.amountMinor, account.currency))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.red : Color.secondary.opacity(0.45))
        }
        .contentShape(Rectangle())
    }

    private var canSave: Bool {
        !accounts.isEmpty && !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount > 0 && !accountId.isEmpty && (!needsSettlementAmount || parsedSettlementAmount > 0)
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

    private func money(_ amount: Int, _ code: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: code).presentation(.isoCode))
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }
    private var parsedSettlementAmount: Int {
        let decimal = Decimal(string: settlementAmount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func selectDefaultAccount() {
        if accounts.contains(where: { $0.id == accountId }) { return }
        accountId = accounts.first?.id ?? ""
        if let account = accounts.first { currency = account.currency }
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        let timestamp = ISO8601DateFormatter().string(from: paymentDate)
        let settledAmount = needsSettlementAmount ? parsedSettlementAmount : parsedAmount
        let originalAmount = needsSettlementAmount ? Money(amountMinor: -parsedAmount, currency: currency) : nil
        let transaction = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(),
            accountId: account.id,
            description: name.trimmingCharacters(in: .whitespaces),
            amount: Money(amountMinor: -settledAmount, currency: account.currency),
            originalAmount: originalAmount,
            bookedAt: timestamp,
            pending: false,
            category: category.trimmingCharacters(in: .whitespaces).isEmpty ? "Bills" : category.trimmingCharacters(in: .whitespaces),
            source: "manual",
            expensePurpose: expensePurpose,
            reimbursementStatus: reimbursable ? "pending" : nil,
            updatedAt: timestamp
        ), initialVersion: 0)
        context.insert(transaction)
        context.insert(PendingTransactionCreate(entityId: transaction.id))
        let recurringPayments = (try? context.fetch(FetchDescriptor<RecurringPayment>())) ?? []
        autoLinkRecurringPayment(transaction, payments: recurringPayments, context: context)
        account.amountMinor -= settledAmount
        account.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        dismiss()
    }
}
