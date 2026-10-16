import SwiftData
import SwiftUI
import Observation

@main
struct LedgerlyApp: App {
    @State private var session = SessionController()
    @State private var security = AppSecurityController()
    @State private var screenshots = ScreenshotNotificationController()
    var body: some Scene {
        WindowGroup {
            LedgerlyPrivacyRoot {
                if session.canUseApp { RootTabView().environment(session) }
                else { LoginView().environment(session) }
            }
            .environment(security)
            .environment(screenshots)
        }
            .modelContainer(for: [CachedAccount.self, CachedTransaction.self, SyncSetting.self, PendingMutation.self, PendingAccountMutation.self, PendingTransactionCreate.self, PendingRecurringMutation.self, PendingStockMutation.self, RecurringPayment.self, StockHolding.self, StockTrade.self])
    }
}

@MainActor @Observable final class SessionController {
    var isAuthenticated = KeychainStore().token() != nil
    var localOnly = UserDefaults.standard.bool(forKey: "ledgerly.localOnly")
    var canUseApp: Bool { isAuthenticated || localOnly }
    func complete(_ response: AuthResponse, apiURL: URL, convexURL: URL) {
        KeychainStore().saveToken(response.token)
        // Keep the addresses that this device successfully used. The API's
        // advertised URL can be an internal Docker/localhost address that is
        // not reachable from an iPhone.
        UserDefaults.standard.set(apiURL.absoluteString, forKey: "ledgerly.apiURL")
        UserDefaults.standard.set(convexURL.absoluteString, forKey: "ledgerly.convexURL")
        UserDefaults.standard.set(response.user.username, forKey: "ledgerly.username")
        UserDefaults.standard.set(response.context.syncSessionId, forKey: "ledgerly.syncSessionId")
        UserDefaults.standard.set(false, forKey: "ledgerly.localOnly")
        localOnly = false
        isAuthenticated = true
    }
    func continueLocally() {
        UserDefaults.standard.set(true, forKey: "ledgerly.localOnly")
        localOnly = true
    }
    func logout() {
        Task { try? await APIClient.shared.logout() }
        KeychainStore().deleteToken()
        isAuthenticated = false
    }
    func configureSync() {
        UserDefaults.standard.set(false, forKey: "ledgerly.localOnly")
        localOnly = false
        isAuthenticated = false
    }
}

private struct LoginView: View {
    @Environment(SessionController.self) private var session
    @State private var apiURL = AppConfig.baseURL.absoluteString
    @State private var convexURL = AppConfig.convexURL.absoluteString
    @State private var username = ""
    @State private var password = ""
    @State private var registration = false
    @State private var working = false
    @State private var error: String?
    @State private var registrationEnabled = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(registration ? "Create credentials for your self-hosted server." : "Start locally, or sign in to sync across devices.")
                        .foregroundStyle(.secondary)
                    if !registration {
                        Button { session.continueLocally() } label: {
                            Label("Continue on this iPhone", systemImage: "iphone")
                        }
                    }
                }
                Section("Server") {
                        TextField("API endpoint", text: $apiURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                        TextField("Convex endpoint", text: $convexURL).textContentType(.URL).textInputAutocapitalization(.never).keyboardType(.URL)
                }
                Section("Account") {
                        TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never)
                        SecureField("Password (10+ characters)", text: $password).textContentType(registration ? .newPassword : .password)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button { Task { await submit() } } label: {
                        if working { ProgressView() } else { Text(registration ? "Create account" : "Log in") }
                    }.disabled(working || username.count < 3 || password.count < 10)
                    if registration || registrationEnabled {
                        Button(registration ? "Already have an account? Log in" : "Need an account? Register") { registration.toggle(); error = nil }
                    }
                }
            }
            .navigationTitle(registration ? "Create account" : "Ledgerly")
        }
        .task { await loadServerConfig() }
    }

    private func submit() async {
        guard let api = URL(string: apiURL), let convex = URL(string: convexURL), ["http", "https"].contains(api.scheme), ["http", "https"].contains(convex.scheme) else { error = "Enter valid HTTP(S) endpoint URLs."; return }
        working = true; error = nil
        UserDefaults.standard.set(api.absoluteString, forKey: "ledgerly.apiURL")
        do {
            let response = try await APIClient.shared.authenticate(username: username, password: password, convexURL: convex, register: registration)
            session.complete(response, apiURL: api, convexURL: convex)
        } catch APIError.http(let status, let message) {
            error = message ?? (status == 401 ? "Invalid username or password." : "Server rejected the request (\(status)).")
        }
        catch { self.error = "Could not reach the server." }
        working = false
    }

    private func loadServerConfig() async {
        UserDefaults.standard.set(apiURL, forKey: "ledgerly.apiURL")
        if let config = try? await APIClient.shared.serverConfig() {
            registrationEnabled = config.registrationEnabled
            if UserDefaults.standard.string(forKey: "ledgerly.convexURL") == nil { convexURL = config.convexUrl }
        }
    }
}

private struct RootTabView: View {
    private enum RootTab: Hashable { case overview, accounts, add, activity, settings }
    private enum AddFlow: String, Identifiable { case quickSpend, recurring, moneyIn, moneyOut, transfer; var id: String { rawValue } }
    @State private var selection = RootTab.overview
    @State private var previousSelection = RootTab.overview
    @State private var addFlow: AddFlow?
    @State private var showingDraggedQuickAdd = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Insights", systemImage: AppIcon.insights, value: RootTab.overview) {
                DashboardView()
            }

            Tab("Accounts", systemImage: AppIcon.accounts, value: RootTab.accounts) {
                NativeAccountsView()
            }

            Tab(value: RootTab.add) {
                Color.clear
            } label: {
                Label("Add", systemImage: "plus.circle.fill")
            }

            Tab("Activity", systemImage: AppIcon.activity, value: RootTab.activity) {
                NativeActivityView()
            }

            Tab("Settings", systemImage: AppIcon.settings, value: RootTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(.blue)
        .onChange(of: selection) { oldValue, newValue in
            if newValue == .add {
                selection = oldValue == .add ? previousSelection : oldValue
                showingDraggedQuickAdd = true
            } else {
                previousSelection = newValue
            }
        }
        .overlay(alignment: .bottom) {
            Menu {
                Button("Quick spend", systemImage: "bolt.fill") { addFlow = .quickSpend }
                Button("Add money", systemImage: "plus.circle.fill") { addFlow = .moneyIn }
                Button("Spend money", systemImage: "minus.circle.fill") { addFlow = .moneyOut }
                Button("Transfer money", systemImage: "arrow.left.arrow.right.circle.fill") { addFlow = .transfer }
                Divider()
                Button("Recurring bill", systemImage: "repeat") { addFlow = .recurring }
            } label: {
                Color.clear
                .frame(width: 74, height: 50)
                .contentShape(Rectangle())
            } primaryAction: {
                addFlow = .quickSpend
            }
            .accessibilityLabel("Add")
            .accessibilityHint("Opens quick spend. Touch and hold for more actions")
            .padding(.bottom, 1)
        }
        .confirmationDialog("Quick Add", isPresented: $showingDraggedQuickAdd, titleVisibility: .visible) {
            Button("Quick spend", systemImage: "bolt.fill") { addFlow = .quickSpend }
            Button("Add money", systemImage: "plus.circle.fill") { addFlow = .moneyIn }
            Button("Spend money", systemImage: "minus.circle.fill") { addFlow = .moneyOut }
            Button("Transfer money", systemImage: "arrow.left.arrow.right.circle.fill") { addFlow = .transfer }
            Button("Recurring bill", systemImage: "repeat") { addFlow = .recurring }
        }
        .sheet(item: $addFlow) { flow in
            switch flow {
            case .quickSpend: QuickSpendView()
            case .recurring: NewRecurringPaymentView()
            case .moneyIn: AccountEntryView(direction: .moneyIn)
            case .moneyOut: AccountEntryView(direction: .moneyOut)
            case .transfer: AccountTransferView()
            }
        }
        .task { openPendingAddFlow() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            openPendingAddFlow()
        }
    }

    private func openPendingAddFlow() {
        guard UserDefaults.standard.string(forKey: "ledgerly.pendingAddFlow") == "moneyIn" else { return }
        UserDefaults.standard.removeObject(forKey: "ledgerly.pendingAddFlow")
        addFlow = .moneyIn
    }
}

struct NewAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var institution = ""
    @State private var kind = "checking"
    @State private var balance = ""
    @State private var currency = SupportedCurrency.defaultCode
    private let kinds = [("checking", "Checking"), ("savings", "Savings"), ("credit", "Credit card"), ("sharedCredit", "Someone else's card"), ("investment", "Investment"), ("cash", "Cash")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Name", text: $name)
                    TextField("Institution (optional)", text: $institution)
                    Picker("Type", selection: $kind) { ForEach(kinds, id: \.0) { Text($0.1).tag($0.0) } }
                }
                Section("Opening balance") {
                    TextField("0.00", text: $balance).keyboardType(.decimalPad)
                    Picker("Currency", selection: $currency) {
                        ForEach(SupportedCurrency.all) { option in
                            Text("\(option.code) — \(option.name)").tag(option.code)
                        }
                    }
                }
                if kind == "sharedCredit" {
                    Section {
                        Text("Use this for a parent’s or someone else’s card. It stays visible in Overview but is excluded from your own net worth.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Section { Text("This account is saved locally. You can enable sync later in Settings.").font(.subheadline).foregroundStyle(.secondary) }
            }
            .navigationTitle("New account").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
        }
    }

    private func save() {
        let decimal = Decimal(string: balance.replacingOccurrences(of: ",", with: ".")) ?? 0
        let minor = NSDecimalNumber(decimal: decimal * 100).intValue
        let account = CachedAccount(name: name.trimmingCharacters(in: .whitespaces), institution: institution.trimmingCharacters(in: .whitespaces).isEmpty ? "Manual" : institution.trimmingCharacters(in: .whitespaces), kind: kind, amountMinor: minor, currency: currency)
        context.insert(account)
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        dismiss()
    }
}

struct NewRecurringPaymentView: View {
    private enum Step: Int {
        case account, amount, schedule, details

        var title: String {
            switch self {
            case .account: "Choose account"
            case .amount: "Enter amount"
            case .schedule: "Schedule"
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
    @State private var currency = SupportedCurrency.defaultCode
    @State private var frequency = "monthly"
    @State private var nextDate = Date()
    @State private var accountId = ""
    @State private var category = "Bills"
    @State private var step: Step = .account
    @State private var movesForward = true
    private let existingPayment: RecurringPayment?
    private let transactionID: String?
    private let onSave: ((RecurringPayment) -> Void)?
    private let frequencies = [("weekly", "Weekly"), ("everyTwoWeeks", "Every 2 weeks"), ("monthly", "Monthly"), ("yearly", "Yearly"), ("everyTwoYears", "Every 2 years")]

    init(payment: RecurringPayment? = nil) {
        existingPayment = payment
        transactionID = nil
        onSave = nil
        if let payment {
            _name = State(initialValue: payment.name)
            _amount = State(initialValue: NSDecimalNumber(value: Double(payment.amountMinor) / 100).stringValue)
            _currency = State(initialValue: payment.currency)
            _frequency = State(initialValue: payment.frequency)
            _nextDate = State(initialValue: payment.nextDate)
            _accountId = State(initialValue: payment.accountId ?? "")
            _category = State(initialValue: payment.category)
        }
    }

    init(transaction: TransactionSnapshot, onSave: ((RecurringPayment) -> Void)? = nil) {
        existingPayment = nil
        transactionID = transaction.id
        self.onSave = onSave
        let purchaseAmount = transaction.originalAmountMinor ?? transaction.amountMinor
        _name = State(initialValue: transaction.title)
        _amount = State(initialValue: NSDecimalNumber(value: Double(abs(purchaseAmount)) / 100).stringValue)
        _currency = State(initialValue: transaction.originalCurrency ?? transaction.currency)
        _nextDate = State(initialValue: Calendar.current.date(byAdding: .month, value: 1, to: transaction.bookedDate ?? Date()) ?? Date())
        _accountId = State(initialValue: transaction.accountID)
        _category = State(initialValue: transaction.category ?? "Bills")
    }

    private var availableAccounts: [CachedAccount] { accounts }
    private var selectedAccount: CachedAccount? { accounts.first { $0.id == accountId } }

    var body: some View {
        NavigationStack {
            Group {
                if existingPayment != nil {
                    editForm
                } else {
                    ZStack {
                        switch step {
                        case .account: accountStep
                        case .amount: amountStep
                        case .schedule: scheduleStep
                        case .details: detailsStep
                        }
                    }
                    .id(step)
                    .transition(stepTransition)
                }
            }
            .navigationTitle(existingPayment == nil ? step.title : "Edit recurring bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if existingPayment != nil || step == .account { Button("Cancel") { dismiss() } }
                    else { Button("Back", systemImage: "chevron.left") { goBack() } }
                }
                if existingPayment != nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
                } else if step != .account {
                    ToolbarItem(placement: .confirmationAction) { Button("Cancel") { dismiss() } }
                }
            }
            .task { selectDefaultAccount() }
        }
    }

    private var editForm: some View {
        Form {
            Section { MoneyAmountHeader(title: "Amount", amount: $amount, currency: $currency) }
            Section("Bill") { TextField("Name", text: $name); TransactionCategoryPicker(selection: $category) }
            Section("Repeats") { frequencyPicker; DatePicker("Next payment", selection: $nextDate, displayedComponents: .date) }
            Section("Account") {
                Picker("Pay from", selection: $accountId) {
                    Text("Not selected").tag("")
                    ForEach(availableAccounts) { Text("\($0.name) · \($0.currency)").tag($0.id) }
                }
            }
        }
    }

    private var accountStep: some View {
        Form {
            Section { FlowStepHeader(current: 1, total: 4, instruction: "Which account usually pays this bill?") }
                .listRowBackground(Color.clear)
            Section("Pay from") {
                ForEach(availableAccounts) { account in
                    Button {
                        accountId = account.id
                        if amount.isEmpty { currency = account.currency }
                    } label: { accountRow(account, selected: account.id == accountId) }
                        .buttonStyle(.plain)
                }
                Button { accountId = "" } label: {
                    Label("No account", systemImage: accountId.isEmpty ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
            }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Enter amount", systemImage: "arrow.right", tint: .blue, disabled: false) { goForward(to: .amount) }
        }
    }

    private var amountStep: some View {
        Form {
            Section {
                FlowStepHeader(current: 2, total: 4, instruction: selectedAccount?.name ?? "Recurring amount")
                MoneyAmountHeader(title: "Amount", amount: $amount, currency: $currency, tint: .blue)
            }
            .listRowBackground(Color.clear)
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Choose schedule", systemImage: "arrow.right", tint: .blue, disabled: parsedAmount <= 0) { goForward(to: .schedule) }
        }
    }

    private var scheduleStep: some View {
        Form {
            Section { FlowStepHeader(current: 3, total: 4, instruction: "When does it repeat?") }
                .listRowBackground(Color.clear)
            Section("Repeats") { frequencyPicker; DatePicker("Next payment", selection: $nextDate, displayedComponents: .date) }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Additional information", systemImage: "arrow.right", tint: .blue, disabled: false) { goForward(to: .details) }
        }
    }

    private var detailsStep: some View {
        Form {
            Section { FlowStepHeader(current: 4, total: 4, instruction: "Review and save") }
                .listRowBackground(Color.clear)
            Section("Summary") {
                LabeledContent("Account", value: selectedAccount?.name ?? "No account")
                LabeledContent("Amount", value: recurringMoney(parsedAmount, currency))
                LabeledContent("Schedule", value: frequencies.first(where: { $0.0 == frequency })?.1 ?? frequency)
            }
            Section("Bill") { TextField("Name", text: $name); TransactionCategoryPicker(selection: $category) }
            Section { Text("Ledgerly tracks this schedule. It does not move money or charge the account.").font(.subheadline).foregroundStyle(.secondary) }
        }
        .safeAreaInset(edge: .bottom) {
            FlowButton(title: "Add recurring bill", systemImage: "repeat", tint: .blue, disabled: !canSave, action: save)
        }
    }

    private var frequencyPicker: some View {
        Picker("Repeats", selection: $frequency) { ForEach(frequencies, id: \.0) { Text($0.1).tag($0.0) } }
    }

    private func accountRow(_ account: CachedAccount, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: AppIcon.account(kind: account.kind)).ledgerlyIcon()
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.headline).foregroundStyle(.primary)
                Text("\(account.institution) · \(recurringMoney(account.amountMinor, account.currency))").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.blue : Color.secondary.opacity(0.45))
        }
        .contentShape(Rectangle())
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount > 0 }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        movesForward = false
        withAnimation(stepAnimation) { step = previous }
    }

    private func goForward(to next: Step) {
        movesForward = true
        withAnimation(stepAnimation) { step = next }
    }

    private var stepAnimation: Animation? { reduceMotion ? nil : .snappy(duration: 0.38, extraBounce: 0.04) }
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: movesForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movesForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func recurringMoney(_ amount: Int, _ code: String) -> String {
        (Double(amount) / 100).formatted(.currency(code: code).presentation(.isoCode))
    }

    private var parsedAmount: Int {
        let decimal = Decimal(string: amount.replacingOccurrences(of: ",", with: ".")) ?? 0
        return NSDecimalNumber(decimal: decimal * 100).intValue
    }

    private func save() {
        let bill = existingPayment ?? RecurringPayment(name: name, amountMinor: parsedAmount, currency: currency, frequency: frequency, nextDate: nextDate, accountId: nil, category: category)
        bill.name = name.trimmingCharacters(in: .whitespaces)
        bill.amountMinor = parsedAmount
        bill.currency = currency
        bill.frequency = frequency
        bill.nextDate = nextDate
        bill.accountId = accountId.isEmpty ? nil : accountId
        bill.category = category.trimmingCharacters(in: .whitespaces).isEmpty ? "Bills" : category.trimmingCharacters(in: .whitespaces)
        if existingPayment == nil { context.insert(bill) }
        context.insert(PendingRecurringMutation(entityId: bill.id, action: "upsert"))
        let transactions = (try? context.fetch(FetchDescriptor<CachedTransaction>())) ?? []
        if let transactionID, let transaction = transactions.first(where: { $0.id == transactionID }) {
            transaction.recurringPaymentId = bill.id
            transaction.updatedAt = ISO8601DateFormatter().string(from: Date())
            enqueueFullTransaction(context: context, transactionID: transaction.id)
        }
        for transaction in transactions where transaction.recurringPaymentId == nil { autoLinkRecurringPayment(transaction, payments: [bill], context: context) }
        try? context.save()
        onSave?(bill)
        dismiss()
    }

    private func selectDefaultAccount() {
        if availableAccounts.contains(where: { $0.id == accountId }) { return }
        accountId = availableAccounts.first(where: { $0.currency == currency })?.id ?? availableAccounts.first?.id ?? ""
    }
}
