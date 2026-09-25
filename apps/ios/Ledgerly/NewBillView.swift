import SwiftData
import SwiftUI

struct NewBillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
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

    private var selectedAccount: CachedAccount? { accounts.first { $0.id == accountId } }
    private var needsSettlementAmount: Bool { selectedAccount.map { $0.currency != currency } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                if accounts.isEmpty {
                    ContentUnavailableView(
                        "Create an account first",
                        systemImage: "building.columns",
                        description: Text("A one-time bill needs an account to pay from.")
                    )
                } else {
                    Section("Bill") {
                        TextField("Name", text: $name)
                        MoneyEntryRow(label: "Purchase amount", amount: $amount, currency: $currency)
                        TransactionCategoryPicker(selection: $category)
                    }

                    Section("For") {
                        Picker("Purpose", selection: $expensePurpose) {
                            Text("Personal").tag("personal")
                            Text("School").tag("school")
                            Text("Someone else").tag("someoneElse")
                        }
                        Toggle("I expect reimbursement", isOn: $reimbursable)
                    }

                    Section {
                        DatePicker("Payment date", selection: $paymentDate, displayedComponents: .date)
                        Picker("Pay from", selection: $accountId) {
                            ForEach(accounts) { Text("\($0.name) · \($0.currency)").tag($0.id) }
                        }
                        if let account = selectedAccount, needsSettlementAmount {
                            TextField("Amount charged in \(account.currency)", text: $settlementAmount)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Text("Payment")
                    } footer: {
                        Text(needsSettlementAmount ? "Enter the original purchase and the amount your bank charged after conversion." : "A one-time bill has one payment date and does not repeat.")
                    }
                }
            }
            .navigationTitle("Add one-time bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(accounts.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount <= 0 || accountId.isEmpty || (needsSettlementAmount && parsedSettlementAmount <= 0))
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
