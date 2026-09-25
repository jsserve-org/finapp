import AppIntents
import Foundation

struct ShortcutBillRequest: Encodable {
    let id: String
    let type: String
    let name: String
    let amountMinor: Int
    let currency: String
    let date: String?
    let accountId: String?
    let category: String
    let frequency: String?
    let nextDate: String?
}

struct BillAccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ledgerly Account")
    static let defaultQuery = BillAccountQuery()

    let id: String
    let name: String
    let institution: String
    let currency: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(institution) · \(currency)")
    }
}

struct BillAccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BillAccountEntity] {
        try await entities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BillAccountEntity] {
        try await entities()
    }

    private func entities() async throws -> [BillAccountEntity] {
        try await APIClient.shared.accounts().map {
            BillAccountEntity(id: $0.id, name: $0.name, institution: $0.institution, currency: $0.balance.currency)
        }
    }
}

enum BillFrequency: String, AppEnum {
    case weekly, everyTwoWeeks, monthly, yearly, everyTwoYears

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Frequency")
    static let caseDisplayRepresentations: [BillFrequency: DisplayRepresentation] = [
        .weekly: "Weekly", .everyTwoWeeks: "Every 2 weeks", .monthly: "Monthly", .yearly: "Yearly", .everyTwoYears: "Every 2 years",
    ]
}

struct AddOneTimeBillIntent: AppIntent {
    static let title: LocalizedStringResource = "Spend Money"
    static let description = IntentDescription("Record a one-time expense in Ledgerly and subtract it from an account.")

    @Parameter(title: "Name") var name: String
    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Account") var account: BillAccountEntity
    @Parameter(title: "Payment Date") var paymentDate: Date
    @Parameter(title: "Category", default: "Bills") var category: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { throw BillShortcutError.invalidAmount }
        let formatter = ISO8601DateFormatter()
        let request = ShortcutBillRequest(
            id: UUID().uuidString.lowercased(), type: "oneTime", name: name,
            amountMinor: Int((amount * 100).rounded()), currency: account.currency,
            date: formatter.string(from: paymentDate), accountId: account.id, category: category,
            frequency: nil, nextDate: nil
        )
        _ = try await APIClient.shared.createBill(request)
        return .result(dialog: "Recorded \(name) in Ledgerly.")
    }
}

struct AddRecurringBillIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Recurring Bill"
    static let description = IntentDescription("Create a recurring bill in Ledgerly.")

    @Parameter(title: "Name") var name: String
    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Account") var account: BillAccountEntity
    @Parameter(title: "Next Payment") var nextPayment: Date
    @Parameter(title: "Frequency") var frequency: BillFrequency
    @Parameter(title: "Category", default: "Bills") var category: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else { throw BillShortcutError.invalidAmount }
        let formatter = ISO8601DateFormatter()
        let request = ShortcutBillRequest(
            id: UUID().uuidString.lowercased(), type: "recurring", name: name,
            amountMinor: Int((amount * 100).rounded()), currency: account.currency,
            date: nil, accountId: account.id, category: category,
            frequency: frequency.rawValue, nextDate: formatter.string(from: nextPayment)
        )
        _ = try await APIClient.shared.createBill(request)
        return .result(dialog: "Created recurring bill \(name) in Ledgerly.")
    }
}

enum BillShortcutError: Error, CustomLocalizedStringResourceConvertible {
    case invalidAmount
    var localizedStringResource: LocalizedStringResource { "Amount must be greater than zero." }
}

struct OpenAddMoneyIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Money"
    static let description = IntentDescription("Open Ledgerly and choose the account to add money to.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        UserDefaults.standard.set("moneyIn", forKey: "ledgerly.pendingAddFlow")
        return .result(dialog: "Choose the account in Ledgerly, then enter the amount.")
    }
}

struct LedgerlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddOneTimeBillIntent(),
            phrases: ["Spend money in \(.applicationName)", "Record an expense in \(.applicationName)"],
            shortTitle: "Spend Money",
            systemImageName: "minus.circle.fill"
        )
        AppShortcut(
            intent: AddRecurringBillIntent(),
            phrases: ["Add a recurring bill in \(.applicationName)"],
            shortTitle: "Add Recurring Bill",
            systemImageName: "repeat"
        )
        AppShortcut(
            intent: OpenAddMoneyIntent(),
            phrases: ["Add money in \(.applicationName)", "Deposit money in \(.applicationName)"],
            shortTitle: "Add Money",
            systemImageName: "plus.circle.fill"
        )
    }
}
