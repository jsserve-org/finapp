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
    let account: CachedAccount
    let direction: AccountEntryDirection
    @State private var description = ""
    @State private var amount = ""
    @State private var category = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Account", value: account.name)
                    LabeledContent("Currency", value: account.currency)
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                } header: { Text(direction.title) }
                Section("Details") {
                    TextField("Description", text: $description)
                    TextField("Category", text: $category)
                    DatePicker("Date", selection: $date)
                }
                Section {
                    Text(direction == .moneyIn
                         ? "This increases the account balance and appears as green money in."
                         : "This decreases the account balance and appears as red money out.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(direction.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(parsedAmount <= 0) }
            }
            .task {
                if description.isEmpty { description = direction.defaultDescription }
                if category.isEmpty { category = direction.defaultCategory }
            }
        }
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save() {
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
    let source: CachedAccount
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    @State private var destinationID = ""
    @State private var amount = ""
    @State private var note = "Transfer"
    @State private var date = Date()

    private var destinations: [CachedAccount] {
        accounts.filter { $0.id != source.id && $0.currency == source.currency }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transfer") {
                    LabeledContent("From", value: source.name)
                    Picker("To", selection: $destinationID) {
                        ForEach(destinations) { Text($0.name).tag($0.id) }
                    }
                    TextField("Amount", text: $amount).keyboardType(.decimalPad)
                    LabeledContent("Currency", value: source.currency)
                }
                Section("Details") {
                    TextField("Description", text: $note)
                    DatePicker("Date", selection: $date)
                }
                if destinations.isEmpty {
                    Section { Text("Create another \(source.currency) account before transferring money.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Transfer money")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Transfer") { transfer() }.disabled(parsedAmount <= 0 || destinationID.isEmpty) }
            }
            .task { if destinationID.isEmpty { destinationID = destinations.first?.id ?? "" } }
        }
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func transfer() {
        guard let destination = accounts.first(where: { $0.id == destinationID }) else { return }
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
