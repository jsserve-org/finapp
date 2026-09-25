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

struct MoneyAmountHeader: View {
    let title: String
    @Binding var amount: String
    @Binding var currency: String
    var tint: Color = .primary
    var currencyLocked = false
    @FocusState private var amountIsFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("0", text: $amount)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .keyboardType(.decimalPad)
                .focused($amountIsFocused)
                .minimumScaleFactor(0.55)
            if currencyLocked {
                Text(currency)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 6)
                    .background(.tertiary, in: Capsule())
                    .accessibilityLabel("Currency")
                    .accessibilityValue(currency)
            } else {
                Menu {
                    ForEach(SupportedCurrency.all) { option in
                        Button {
                            currency = option.code
                        } label: {
                            if currency == option.code {
                                Label("\(option.code) — \(option.name)", systemImage: "checkmark")
                            } else {
                                Text("\(option.code) — \(option.name)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(currency)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.secondary)
                .accessibilityLabel("Currency")
                .accessibilityValue(currency)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .task {
            await Task.yield()
            amountIsFocused = true
        }
    }
}
