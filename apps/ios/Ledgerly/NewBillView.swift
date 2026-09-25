import SwiftData
import SwiftUI

struct NewBillView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var name = ""
    @State private var amount = ""
    @State private var currency = SupportedCurrency.defaultCode
    @State private var category = "Bills"
    @State private var paymentDate = Date()
    @State private var accountId = ""
    @State private var expensePurpose = "personal"
    @State private var reimbursable = false

    private var availableAccounts: [CachedAccount] { accounts.filter { $0.currency == currency } }

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
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                        Picker("Currency", selection: $currency) {
                            ForEach(SupportedCurrency.all) { option in
                                Text("\(option.code) — \(option.name)").tag(option.code)
                            }
                        }
                        TextField("Category", text: $category)
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
                            ForEach(availableAccounts) { Text($0.name).tag($0.id) }
                        }
                    } header: {
                        Text("Payment")
                    } footer: {
                        Text("A one-time bill has one payment date and does not repeat.")
                    }
                }
            }
            .navigationTitle("Add one-time bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(accounts.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty || parsedAmount <= 0 || accountId.isEmpty)
                }
            }
            .task { selectDefaultAccount() }
            .onChange(of: currency) { _, _ in selectDefaultAccount(force: true) }
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

    private func selectDefaultAccount(force: Bool = false) {
        if !force, accountId.isEmpty, availableAccounts.isEmpty, let first = accounts.first {
            currency = first.currency
            accountId = first.id
            return
        }
        if !force, availableAccounts.contains(where: { $0.id == accountId }) { return }
        accountId = availableAccounts.first?.id ?? ""
    }

    private func save() {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        let timestamp = ISO8601DateFormatter().string(from: paymentDate)
        let transaction = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(),
            accountId: account.id,
            description: name.trimmingCharacters(in: .whitespaces),
            amount: Money(amountMinor: -parsedAmount, currency: currency),
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
        account.amountMinor -= parsedAmount
        account.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        dismiss()
    }
}
