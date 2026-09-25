import SwiftUI

enum TransactionCategory {
    static let common = [
        "Bills", "Dining", "Groceries", "Shopping", "Transport", "Housing",
        "School", "Health", "Travel", "Subscriptions", "Deposit", "Refund", "Transfer",
    ]
}

struct TransactionCategoryPicker: View {
    @Binding var selection: String
    @State private var showingCustom = false
    @State private var customCategory = ""

    var body: some View {
        Menu {
            ForEach(TransactionCategory.common, id: \.self) { category in
                Button {
                    selection = category
                } label: {
                    Label(category, systemImage: selection == category ? "checkmark" : PaymentIcon.symbol(title: "", category: category, amountMinor: -1))
                }
            }
            Divider()
            Button("Custom category…", systemImage: "pencil") {
                customCategory = TransactionCategory.common.contains(selection) ? "" : selection
                showingCustom = true
            }
        } label: {
            LabeledContent("Category", value: selection.isEmpty ? "Uncategorized" : selection)
        }
        .foregroundStyle(.primary)
        .alert("Custom category", isPresented: $showingCustom) {
            TextField("Category name", text: $customCategory)
            Button("Cancel", role: .cancel) {}
            Button("Use category") {
                let clean = customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { selection = clean }
            }
        } message: {
            Text("This category will be used for transaction icons, search, and spending insights.")
        }
    }
}

struct MoneyEntryRow: View {
    let label: String
    @Binding var amount: String
    @Binding var currency: String

    var body: some View {
        HStack(spacing: 10) {
            TextField(label, text: $amount)
                .keyboardType(.decimalPad)
            Picker("Currency", selection: $currency) {
                ForEach(SupportedCurrency.all) { option in
                    Text(option.code).tag(option.code)
                }
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Currency")
        }
    }
}
