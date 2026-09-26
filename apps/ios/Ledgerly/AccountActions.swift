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
    static func record(
        amountMinor: Int,
        description: String,
        category: String,
        date: Date,
        direction: AccountEntryDirection,
        account: CachedAccount,
        context: ModelContext,
        purchaseCurrency: String? = nil,
        expensePurpose: String? = nil,
        expectsReimbursement: Bool = false
    ) {
        let signedAmount = direction == .moneyIn ? amountMinor : -amountMinor
        let enteredCurrency = purchaseCurrency ?? account.currency
        let settlementPending = direction == .moneyOut && enteredCurrency != account.currency
        let recordedAmount = settlementPending ? 0 : signedAmount
        let originalAmount = settlementPending ? Money(amountMinor: signedAmount, currency: enteredCurrency) : nil
        let timestamp = ISO8601DateFormatter().string(from: date)
        let transaction = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(), accountId: account.id,
            description: description, amount: Money(amountMinor: recordedAmount, currency: account.currency),
            originalAmount: originalAmount, bookedAt: timestamp,
            pending: settlementPending, category: category, categoryUserEdited: true, source: "manual", expensePurpose: expensePurpose,
            reimbursementStatus: expectsReimbursement && direction == .moneyOut ? "pending" : nil,
            updatedAt: timestamp
        ), initialVersion: 0)
        context.insert(transaction)
        context.insert(PendingTransactionCreate(entityId: transaction.id))
        let recurringPayments = (try? context.fetch(FetchDescriptor<RecurringPayment>())) ?? []
        autoLinkRecurringPayment(transaction, payments: recurringPayments, context: context)
        if !settlementPending {
            account.amountMinor += signedAmount
            account.updatedAt = ISO8601DateFormatter().string(from: Date())
            context.insert(PendingAccountMutation(entityId: account.id))
        }
        try? context.save()
    }

    @MainActor
    static func transfer(amountMinor: Int, description: String, date: Date, source: CachedAccount, destination: CachedAccount, context: ModelContext) {
        let timestamp = ISO8601DateFormatter().string(from: date)
        let transferID = UUID().uuidString.lowercased()
        let outgoing = CachedTransaction(dto: TransactionDTO(
            id: "\(transferID)-out", accountId: source.id, description: "\(description) to \(destination.name)",
            amount: Money(amountMinor: -amountMinor, currency: source.currency), bookedAt: timestamp,
            pending: false, category: "Transfer", categoryUserEdited: true, source: "transfer", transferId: transferID,
            transferAccountId: destination.id, transferDirection: "outgoing", updatedAt: timestamp
        ), initialVersion: 0)
        let incoming = CachedTransaction(dto: TransactionDTO(
            id: "\(transferID)-in", accountId: destination.id, description: "\(description) from \(source.name)",
            amount: Money(amountMinor: amountMinor, currency: source.currency), bookedAt: timestamp,
            pending: false, category: "Transfer", categoryUserEdited: true, source: "transfer", transferId: transferID,
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
    let direction: AccountEntryDirection
    private let preferredAccountID: String?
    @State private var selectedAccountID: String
    @State private var description = ""
    @State private var amount = ""
    @State private var currency: String
    @State private var category = ""
    @State private var date = Date()
    @State private var expensePurpose = "personal"
    @State private var expectsReimbursement = false
    @State private var step: Step = .account
    @State private var movesForward = true

    init(account: CachedAccount? = nil, direction: AccountEntryDirection) {
        self.direction = direction
        preferredAccountID = account?.id
        _selectedAccountID = State(initialValue: account?.id ?? "")
        _currency = State(initialValue: account?.currency ?? SupportedCurrency.defaultCode)
    }

    private var selectedAccount: CachedAccount? { accounts.first { $0.id == selectedAccountID } }

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
                    ToolbarItem(placement: .confirmationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .task {
                if description.isEmpty { description = direction.defaultDescription }
                if category.isEmpty { category = direction.defaultCategory }
                selectDefaultAccount()
            }
        }
    }

    private var accountStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 1, total: 3, instruction: direction == .moneyIn ? "Where should the money go?" : "Which account paid?")
            }
            .listRowBackground(Color.clear)
            Section("Account") {
                ForEach(accounts) { account in
                    Button {
                        selectedAccountID = account.id
                        currency = account.currency
                    } label: {
                        accountRow(account, selected: account.id == selectedAccountID)
                    }
                    .buttonStyle(.plain)
                }
                if accounts.isEmpty {
                    ContentUnavailableView("No accounts", systemImage: "building.columns", description: Text("Create an account before recording money."))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Enter amount", systemImage: "arrow.right", tint: direction.color, disabled: selectedAccount == nil) {
                goForward(to: .amount)
            }
        }
    }

    private var amountStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 2, total: 3, instruction: selectedAccount?.name ?? "Amount")
                MoneyAmountHeader(
                    title: direction == .moneyIn ? "Money in" : "Purchase amount",
                    amount: $amount,
                    currency: $currency,
                    tint: direction.color,
                    currencyLocked: direction == .moneyIn
                )
            }
            .listRowBackground(Color.clear)
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Additional information", systemImage: "arrow.right", tint: direction.color, disabled: parsedAmount <= 0) {
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
                if settlementPending {
                    LabeledContent("Bank charge", value: "Waiting for bank")
                }
            }
            Section("Optional details") {
                TextField("Description", text: $description)
                TransactionCategoryPicker(selection: $category)
                DatePicker("Date", selection: $date)
            }
            if direction == .moneyOut {
                if settlementPending {
                    Section {
                        Label("The account balance will not change yet.", systemImage: "clock")
                    } footer: {
                        Text("Ledgerly records the purchase now. Your later bank import can provide the final \(selectedAccount?.currency ?? "account") charge.")
                    }
                }
                Section("For") {
                    Picker("Purpose", selection: $expensePurpose) {
                        Text("Personal").tag("personal")
                        Text("School").tag("school")
                        Text("Someone else").tag("someoneElse")
                    }
                    Toggle("I expect reimbursement", isOn: $expectsReimbursement)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(
                title: direction.title,
                systemImage: direction.symbol,
                tint: direction.color,
                disabled: parsedAmount <= 0 || selectedAccount == nil,
                action: save
            )
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
        if let selectedAccount {
            currency = selectedAccount.currency
            return
        }
        selectedAccountID = accounts.first(where: { $0.id == preferredAccountID })?.id ?? accounts.first?.id ?? ""
        if let selectedAccount { currency = selectedAccount.currency }
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

    private var settlementPending: Bool {
        direction == .moneyOut && selectedAccount?.currency != currency
    }

    private func save() {
        guard let account = selectedAccount else { return }
        let cleanDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        AccountActionService.record(
            amountMinor: parsedAmount,
            description: cleanDescription.isEmpty ? direction.defaultDescription : cleanDescription,
            category: cleanCategory.isEmpty ? direction.defaultCategory : cleanCategory,
            date: date, direction: direction, account: account, context: context,
            purchaseCurrency: currency,
            expensePurpose: direction == .moneyOut ? expensePurpose : nil,
            expectsReimbursement: expectsReimbursement
        )
        dismiss()
    }
}

struct AccountTransferView: View {
    private enum Step: Int {
        case source
        case destination
        case amount
        case details

        var title: String {
            switch self {
            case .source: "From account"
            case .destination: "To account"
            case .amount: "Transfer amount"
            case .details: "Additional information"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \CachedAccount.name) private var accounts: [CachedAccount]
    private let preferredSourceID: String?
    @State private var sourceID: String
    @State private var destinationID = ""
    @State private var amount = ""
    @State private var currency: String
    @State private var note = "Transfer"
    @State private var date = Date()
    @State private var step: Step = .source
    @State private var movesForward = true

    init(source: CachedAccount? = nil) {
        preferredSourceID = source?.id
        _sourceID = State(initialValue: source?.id ?? "")
        _currency = State(initialValue: source?.currency ?? SupportedCurrency.defaultCode)
    }

    private var source: CachedAccount? { accounts.first { $0.id == sourceID } }
    private var destination: CachedAccount? { accounts.first { $0.id == destinationID } }
    private var destinations: [CachedAccount] { accounts.filter { $0.currency == currency && $0.id != sourceID } }

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .source: sourceStep
                case .destination: destinationStep
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
                    if step == .source {
                        Button("Cancel") { dismiss() }
                    } else {
                        Button("Back", systemImage: "chevron.left") { goBack() }
                    }
                }
                if step != .source {
                    ToolbarItem(placement: .confirmationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .task { selectDefaults() }
        }
    }

    private var sourceStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 1, total: 4, instruction: "Choose the account sending money")
            }
            .listRowBackground(Color.clear)
            Section("From") {
                ForEach(accounts) { account in
                    Button {
                        sourceID = account.id
                        currency = account.currency
                        selectDefaultDestination()
                    } label: { accountRow(account, selected: account.id == sourceID) }
                        .buttonStyle(.plain)
                }
                if accounts.isEmpty {
                    ContentUnavailableView("No accounts", systemImage: "building.columns", description: Text("Create an account before making a transfer."))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Choose destination", systemImage: "arrow.right", tint: .blue, disabled: source == nil) {
                goForward(to: .destination)
            }
        }
    }

    private var destinationStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 2, total: 4, instruction: "Where should the money go?")
            }
            .listRowBackground(Color.clear)
            Section("To") {
                ForEach(destinations) { account in
                    Button { destinationID = account.id } label: { accountRow(account, selected: account.id == destinationID) }
                        .buttonStyle(.plain)
                }
                if destinations.isEmpty {
                    ContentUnavailableView("No destination", systemImage: "arrow.left.arrow.right", description: Text("Add another \(currency) account to transfer money."))
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Enter amount", systemImage: "arrow.right", tint: .blue, disabled: destination == nil) {
                goForward(to: .amount)
            }
        }
    }

    private var amountStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 3, total: 4, instruction: transferRoute)
                MoneyAmountHeader(title: "Transfer amount", amount: $amount, currency: $currency, tint: .blue, currencyLocked: true)
            }
            .listRowBackground(Color.clear)
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Additional information", systemImage: "arrow.right", tint: .blue, disabled: parsedAmount <= 0) {
                goForward(to: .details)
            }
        }
    }

    private var detailsStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 4, total: 4, instruction: "Review and transfer")
            }
            .listRowBackground(Color.clear)
            Section("Summary") {
                LabeledContent("From", value: source?.name ?? "")
                LabeledContent("To", value: destination?.name ?? "")
                LabeledContent("Amount", value: money(parsedAmount, currency))
            }
            Section("Optional details") {
                TextField("Description", text: $note)
                DatePicker("Date", selection: $date)
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Transfer money", systemImage: "arrow.left.arrow.right.circle.fill", tint: .blue, disabled: parsedAmount <= 0 || source == nil || destination == nil, action: transfer)
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
        if !accounts.contains(where: { $0.id == sourceID }) {
            sourceID = accounts.first(where: { $0.id == preferredSourceID })?.id ?? accounts.first?.id ?? ""
        }
        if let source { currency = source.currency }
        selectDefaultDestination()
    }

    private func selectDefaultDestination() {
        if destinations.contains(where: { $0.id == destinationID }) { return }
        destinationID = destinations.first?.id ?? ""
    }

    private func money(_ amount: Int, _ code: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: code).presentation(.isoCode))
    }

    private var transferRoute: String {
        guard let source, let destination else { return "Transfer" }
        return "\(source.name) → \(destination.name)"
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

    private func transfer() {
        guard let source, let destination else { return }
        let title = note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Transfer" : note.trimmingCharacters(in: .whitespacesAndNewlines)
        AccountActionService.transfer(amountMinor: parsedAmount, description: title, date: date, source: source, destination: destination, context: context)
        dismiss()
    }
}

struct FlowStepHeader: View {
    let current: Int
    let total: Int
    let instruction: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Step \(current) of \(total)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: Double(current), total: Double(total))
            Text(instruction)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 4)
    }
}

struct FlowButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(tint)
        .disabled(disabled)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
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
