import SwiftData
import SwiftUI

enum AccountEntryDirection: Equatable {
    case moneyIn
    case moneyOut

    var title: String { self == .moneyIn ? "Add money" : "Spend money" }
    var defaultDescription: String { self == .moneyIn ? "Cash deposit" : "Cash expense" }
    var defaultCategory: String { self == .moneyIn ? "Deposit" : "Cash" }
    var symbol: String { self == .moneyIn ? "plus.circle.fill" : "minus.circle.fill" }
    var color: Color { self == .moneyIn ? .green : .red }
}

enum AccountActionService {
    @MainActor
    static func record(amountMinor: Int, description: String, category: String, date: Date, direction: AccountEntryDirection, account: CachedAccount, context: ModelContext) {
        let signedAmount = direction == .moneyIn ? amountMinor : -amountMinor
        let timestamp = ISO8601DateFormatter().string(from: date)
        let transaction = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(), accountId: account.id,
            description: description, amount: Money(amountMinor: signedAmount, currency: account.currency), bookedAt: timestamp,
            pending: false, category: category, source: "manual", updatedAt: timestamp
        ), initialVersion: 0)
        context.insert(transaction)
        context.insert(PendingTransactionCreate(entityId: transaction.id))
        account.amountMinor += signedAmount
        account.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
    }

    @MainActor
    static func transfer(amountMinor: Int, description: String, date: Date, source: CachedAccount, destination: CachedAccount, context: ModelContext) {
        let timestamp = ISO8601DateFormatter().string(from: date)
        let transferID = UUID().uuidString.lowercased()
        let outgoing = CachedTransaction(dto: TransactionDTO(
            id: "\(transferID)-out", accountId: source.id, description: "\(description) to \(destination.name)",
            amount: Money(amountMinor: -amountMinor, currency: source.currency), bookedAt: timestamp,
            pending: false, category: "Transfer", source: "transfer", transferId: transferID,
            transferAccountId: destination.id, transferDirection: "outgoing", updatedAt: timestamp
        ), initialVersion: 0)
        let incoming = CachedTransaction(dto: TransactionDTO(
            id: "\(transferID)-in", accountId: destination.id, description: "\(description) from \(source.name)",
            amount: Money(amountMinor: amountMinor, currency: source.currency), bookedAt: timestamp,
            pending: false, category: "Transfer", source: "transfer", transferId: transferID,
            transferAccountId: source.id, transferDirection: "incoming", updatedAt: timestamp
        ), initialVersion: 0)
        context.insert(outgoing); context.insert(incoming)
        context.insert(PendingTransactionCreate(entityId: outgoing.id)); context.insert(PendingTransactionCreate(entityId: incoming.id))
        source.amountMinor -= amountMinor; destination.amountMinor += amountMinor
        let now = ISO8601DateFormatter().string(from: Date())
        source.updatedAt = now; destination.updatedAt = now
        context.insert(PendingAccountMutation(entityId: source.id)); context.insert(PendingAccountMutation(entityId: destination.id))
        try? context.save()
    }
}

struct AccountEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    let direction: AccountEntryDirection
    private let preferredAccountID: String?
    @State private var selectedAccountID: String
    @State private var description = ""
    @State private var amount = ""
    @State private var currency: String
    @State private var category = ""
    @State private var date = Date()

    init(account: CachedAccount? = nil, direction: AccountEntryDirection) {
        self.direction = direction
        preferredAccountID = account?.id
        _selectedAccountID = State(initialValue: account?.id ?? "")
        _currency = State(initialValue: account?.currency ?? SupportedCurrency.defaultCode)
    }

    private var compatibleAccounts: [CachedAccount] { accounts.filter { $0.currency == currency } }
    private var selectedAccount: CachedAccount? { accounts.first { $0.id == selectedAccountID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyAmountHeader(title: direction.title, amount: $amount, currency: $currency, tint: direction.color)
                }
                Section("Account") {
                    ForEach(compatibleAccounts) { account in
                        Button { selectedAccountID = account.id } label: { accountRow(account, selected: account.id == selectedAccountID) }
                            .buttonStyle(.plain)
                    }
                    if compatibleAccounts.isEmpty {
                        Text("No \(currency) accounts available.").foregroundStyle(.secondary)
                    }
                }
                Section("Details") {
                    TextField("Description", text: $description)
                    TransactionCategoryPicker(selection: $category)
                    DatePicker("Date", selection: $date)
                }
                Section {
                    Button(direction.title, systemImage: direction.symbol, action: save)
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                        .buttonStyle(.borderedProminent)
                        .tint(direction.color)
                        .controlSize(.large)
                        .disabled(parsedAmount <= 0 || selectedAccount == nil)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle(direction.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                if description.isEmpty { description = direction.defaultDescription }
                if category.isEmpty { category = direction.defaultCategory }
                selectDefaultAccount()
            }
            .onChange(of: currency) { _, _ in selectDefaultAccount() }
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
                .foregroundStyle(selected ? direction.color : Color.secondary.opacity(0.45))
        }
        .contentShape(Rectangle())
    }

    private func selectDefaultAccount() {
        if compatibleAccounts.contains(where: { $0.id == selectedAccountID }) { return }
        selectedAccountID = compatibleAccounts.first(where: { $0.id == preferredAccountID })?.id ?? compatibleAccounts.first?.id ?? ""
    }

    private func money(_ amount: Int, _ code: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: code).presentation(.isoCode))
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save() {
        guard let account = selectedAccount else { return }
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        AccountActionService.record(
            amountMinor: parsedAmount,
            description: cleanDescription.isEmpty ? direction.defaultDescription : cleanDescription,
            category: cleanCategory.isEmpty ? direction.defaultCategory : cleanCategory,
            date: date, direction: direction, account: account, context: context
        )
        dismiss()
    }
}

struct AccountTransferView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    private let preferredSourceID: String?
    @State private var sourceID: String
    @State private var destinationID = ""
    @State private var amount = ""
    @State private var currency: String
    @State private var note = "Transfer"
    @State private var date = Date()

    init(source: CachedAccount? = nil) {
        preferredSourceID = source?.id
        _sourceID = State(initialValue: source?.id ?? "")
        _currency = State(initialValue: source?.currency ?? SupportedCurrency.defaultCode)
    }

    private var compatibleAccounts: [CachedAccount] { accounts.filter { $0.currency == currency } }
    private var source: CachedAccount? { accounts.first { $0.id == sourceID } }
    private var destination: CachedAccount? { accounts.first { $0.id == destinationID } }
    private var destinations: [CachedAccount] { compatibleAccounts.filter { $0.id != sourceID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MoneyAmountHeader(title: "Transfer amount", amount: $amount, currency: $currency, tint: .blue)
                }
                Section("From") {
                    ForEach(compatibleAccounts) { account in
                        Button {
                            sourceID = account.id
                            selectDefaultDestination()
                        } label: {
                            accountRow(account, selected: account.id == sourceID)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section("To") {
                    ForEach(destinations) { account in
                        Button { destinationID = account.id } label: { accountRow(account, selected: account.id == destinationID) }
                            .buttonStyle(.plain)
                    }
                    if destinations.isEmpty { Text("Add another \(currency) account to transfer money.").foregroundStyle(.secondary) }
                }
                Section("Details") {
                    TextField("Description", text: $note)
                    DatePicker("Date", selection: $date)
                }
                Section {
                    Button("Transfer money", systemImage: "arrow.left.arrow.right.circle.fill", action: transfer)
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(parsedAmount <= 0 || source == nil || destination == nil)
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Transfer money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task { selectDefaults() }
            .onChange(of: currency) { _, _ in selectDefaults() }
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
                .foregroundStyle(selected ? Color.blue : Color.secondary.opacity(0.45))
        }
        .contentShape(Rectangle())
    }

    private func selectDefaults() {
        if !compatibleAccounts.contains(where: { $0.id == sourceID }) {
            sourceID = compatibleAccounts.first(where: { $0.id == preferredSourceID })?.id ?? compatibleAccounts.first?.id ?? ""
        }
        selectDefaultDestination()
    }

    private func selectDefaultDestination() {
        if destinations.contains(where: { $0.id == destinationID }) { return }
        destinationID = destinations.first?.id ?? ""
    }

    private func money(_ amount: Int, _ code: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: code).presentation(.isoCode))
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func transfer() {
        guard let source, let destination else { return }
        let title = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Transfer" : note.trimmingCharacters(in: .whitespacesAndNewlines)
        AccountActionService.transfer(amountMinor: parsedAmount, description: title, date: date, source: source, destination: destination, context: context)
        dismiss()
    }
}

struct EditAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let account: CachedAccount
    @State private var name: String
    @State private var institution: String
    @State private var kind: String
    private let kinds = [("checking", "Checking"), ("savings", "Savings"), ("credit", "Credit card"), ("sharedCredit", "Someone else's card"), ("investment", "Investment"), ("cash", "Cash")]

    init(account: CachedAccount) {
        self.account = account
        _name = State(initialValue: account.name)
        _institution = State(initialValue: account.institution)
        _kind = State(initialValue: account.kind)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    TextField("Institution", text: $institution)
                    Picker("Type", selection: $kind) { ForEach(kinds, id: \.0) { Text($0.1).tag($0.0) } }
                    LabeledContent("Currency", value: account.currency)
                }
                Section { Text("Use Add money, Spend, or Transfer to change the balance so every adjustment has a transaction record.").foregroundStyle(.secondary) }
            }
            .navigationTitle("Edit account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func save() {
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.institution = institution.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Manual" : institution.trimmingCharacters(in: .whitespacesAndNewlines)
        account.kind = kind
        account.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        dismiss()
    }
}
