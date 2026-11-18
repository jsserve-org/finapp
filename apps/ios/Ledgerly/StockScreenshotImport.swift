import CryptoKit
import PhotosUI
import SwiftData
import SwiftUI
import Vision

enum StockScreenshotDraft {
    static func number(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Double(text.replacingOccurrences(of: ",", with: "")),
              value.isFinite, value >= 0, value <= 10_000_000 else { return nil }
        return value
    }

    /// Match the TCStock importer's identity so later automatic imports update this position.
    static func holdingID(symbol: String) -> String {
        let hex = SHA256.hash(data: Data("tcstock-symbol|\(symbol)|TWD".utf8)).map { String(format: "%02x", $0) }.joined()
        let chars = Array(hex)
        return "\(String(chars[0..<8]))-\(String(chars[8..<12]))-5\(String(chars[13..<16]))-a\(String(chars[17..<20]))-\(String(chars[20..<32]))"
    }
}

/// Vision coordinates are normalized, with the origin at the lower left.
struct StockScreenshotText: Sendable {
    let text: String
    let box: CGRect
}

struct StockScreenshotRow: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var symbol = ""
    var quantity = ""
    var cost = ""
    var price = ""
    var included = false
    var positionType = "現股"

    var normalizedSymbol: String { symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    var valid: Bool {
        positionType == "現股" && normalizedSymbol.range(of: #"^[0-9A-Z]{4,6}$"#, options: .regularExpression) != nil &&
        StockScreenshotDraft.number(quantity) != nil && StockScreenshotDraft.number(cost) != nil &&
        (StockScreenshotDraft.number(price) ?? 0) > 0
    }
}

enum StockScreenshotTable {
    static func rows(_ words: [StockScreenshotText]) -> [StockScreenshotRow] {
        func clean(_ text: String) -> String {
            text.filter { !$0.isWhitespace && !$0.isPunctuation }
        }
        guard let quantityHeader = words.first(where: { ["庫存股數", "庫仔股數", "持有股數"].contains(clean($0.text)) }) else { return [] }
        let headerY = quantityHeader.box.midY
        let header = words.filter { abs($0.box.midY - headerY) < quantityHeader.box.height * 0.7 }
        func column(_ names: [String]) -> StockScreenshotText? {
            header.first { names.contains(clean($0.text)) }
        }
        guard let product = column(["商品", "股票", "股票名稱"]),
              let cost = column(["成交均價", "平均成本", "成本均價"]),
              let price = column(["市價", "現價"]) else { return [] }
        let columns = header.sorted { $0.box.midX < $1.box.midX }
        func inColumn(_ word: StockScreenshotText, _ heading: StockScreenshotText) -> Bool {
            guard let index = columns.firstIndex(where: { $0.box == heading.box }) else { return false }
            let left = index > 0 ? (columns[index - 1].box.midX + heading.box.midX) / 2 : 0
            let right = index + 1 < columns.count ? (columns[index + 1].box.midX + heading.box.midX) / 2 : 1
            return word.box.midX > left && word.box.midX < right
        }
        let body = words.filter { $0.box.midY < quantityHeader.box.minY }
        // Trade-class cells persist even when neighboring financial values are covered.
        let typeColumn = column(["交易類別", "父易類別"])
        let anchors = body.filter {
            if let typeColumn { return inColumn($0, typeColumn) && ["現股", "融資", "融券"].contains(clean($0.text)) }
            return inColumn($0, quantityHeader) && StockScreenshotDraft.number($0.text) != nil
        }.sorted { $0.box.midY > $1.box.midY }
        return anchors.enumerated().map { index, anchor in
            let top = index == 0 ? quantityHeader.box.minY : (anchors[index - 1].box.midY + anchor.box.midY) / 2
            let bottom = index + 1 < anchors.count ? (anchor.box.midY + anchors[index + 1].box.midY) / 2 : anchor.box.midY - (top - anchor.box.midY)
            let row = body.filter { $0.box.midY < top && $0.box.midY > bottom }
            func cell(_ heading: StockScreenshotText) -> String {
                row.filter { inColumn($0, heading) }.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
            }
            let name = cell(product)
            var result = StockScreenshotRow()
            result.name = name
            if let typeColumn { result.positionType = clean(cell(typeColumn)) }
            // Tickers must come from the product cell, never a quantity, date or cost.
            if let range = name.range(of: #"(?<![0-9A-Za-z])[0-9][0-9A-Za-z]{3,5}(?![0-9A-Za-z])"#, options: .regularExpression) {
                result.symbol = String(name[range]).uppercased()
            }
            result.quantity = cell(quantityHeader)
            result.cost = cell(cost)
            result.price = cell(price)
            result.included = StockScreenshotDraft.number(result.quantity) != nil && StockScreenshotDraft.number(result.cost) != nil && (StockScreenshotDraft.number(result.price) ?? 0) > 0
            return result
        }
    }

    static func recognize(data: Data) throws -> [StockScreenshotText] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Chinese first: English-first recognition mangles the table's Chinese headers.
        request.recognitionLanguages = ["zh-Hant", "en-US"]
        request.usesLanguageCorrection = false
        request.customWords = ["商品", "交易類別", "庫存股數", "成交均價", "投資成本", "市價", "獲利點", "現股"]
        try VNImageRequestHandler(data: data).perform([request])
        return (request.results ?? []).flatMap { observation -> [StockScreenshotText] in
            guard let candidate = observation.topCandidates(1).first else { return [] }
            let text = candidate.string
            guard let regex = try? NSRegularExpression(pattern: #"\S+"#) else { return [] }
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
                guard let range = Range(match.range, in: text), let rectangle = try? candidate.boundingBox(for: range) else { return nil }
                return StockScreenshotText(text: String(text[range]), box: rectangle.boundingBox)
            }
        }
    }
}

struct StockScreenshotImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SessionController.self) private var session
    @Query private var holdings: [StockHolding]
    @State private var photo: PhotosPickerItem?
    @State private var rows: [StockScreenshotRow] = []
    @State private var imageData: Data?
    @State private var recognizedText = ""
    @State private var working = false
    @State private var message: String?
    @State private var sync = SyncController()
    @State private var stocks: [StockIdentity] = []
    @State private var loadingStocks = false
    @State private var editingRow: StockScreenshotRow?

    private var selected: [StockScreenshotRow] { rows.filter { $0.included && $0.valid } }
    private var readyRows: [StockScreenshotRow] { rows.filter(\.valid) }
    private var incompleteRows: [StockScreenshotRow] { rows.filter { !$0.valid } }
    private var valid: Bool {
        !selected.isEmpty && Set(selected.map(\.normalizedSymbol)).count == selected.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PhotosPicker(selection: $photo, matching: .images) {
                        Label(imageData == nil ? "Choose holdings screenshot" : "Choose another screenshot", systemImage: "photo.badge.plus")
                    }
                    if working { ProgressView("Reading holdings…") }
                    if loadingStocks { ProgressView("Matching stock names…") }
                    if stocks.isEmpty && !loadingStocks {
                        Button("Retry stock-name lookup") { Task { await loadStocks() } }
                    }
                    if let imageData, let image = UIImage(data: imageData) {
                        DisclosureGroup("Screenshot") {
                            Image(uiImage: image).resizable().scaledToFit().accessibilityLabel("Selected holdings screenshot")
                        }
                    }
                }
                if let message { Section { Text(message).font(.subheadline).foregroundStyle(.secondary) } }
                if !readyRows.isEmpty {
                    Section {
                        ForEach(readyRows) { row in
                            HStack(spacing: 12) {
                                Button {
                                    if let index = rows.firstIndex(where: { $0.id == row.id }) { rows[index].included.toggle() }
                                } label: {
                                    Image(systemName: row.included ? "checkmark.circle.fill" : "circle")
                                        .font(.title3).foregroundStyle(row.included ? Color.accentColor : .secondary)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel(row.included ? "Exclude \(row.name)" : "Include \(row.name)")
                                Button { editingRow = row } label: { summary(row) }
                                    .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        HStack {
                            Text("Ready · \(readyRows.count)")
                            Spacer()
                            Button(selected.count == readyRows.count ? "Deselect all" : "Select all") {
                                let include = selected.count != readyRows.count
                                for index in rows.indices where rows[index].valid { rows[index].included = include }
                            }.font(.caption).textCase(nil)
                        }
                    } footer: { Text("Tap a position to edit. Import updates existing holdings.") }
                }
                if !incompleteRows.isEmpty {
                    Section {
                        DisclosureGroup("Needs details · \(incompleteRows.count)") {
                            ForEach(incompleteRows) { row in
                                Button { editingRow = row } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(row.name.isEmpty ? "Unidentified position" : row.name).foregroundStyle(.primary)
                                        Text(missingDetails(row)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                    } footer: { Text("These positions are skipped until completed.") }
                }
                Section { Button("Add position manually", systemImage: "plus") { editingRow = StockScreenshotRow(included: true) } }
                if !recognizedText.isEmpty {
                    Section { DisclosureGroup("OCR details") { Text(recognizedText).font(.caption).textSelection(.enabled) } }
                }
            }
            .disabled(working)
            .navigationTitle("Import holdings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(working) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if !selected.isEmpty && !valid {
                        Text("The same stock is selected twice. Deselect one copy.").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { save() } label: {
                        Text("Import \(selected.count) \(selected.count == 1 ? "position" : "positions")")
                            .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).disabled(!valid || working)
                    Text("Holdings only · Cash and trade history stay unchanged")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding().background(.bar)
            }
            .task { await loadStocks() }
            .sheet(item: $editingRow) { row in
                StockImportRowEditor(row: row, stocks: stocks) { updated in
                    if let index = rows.firstIndex(where: { $0.id == updated.id }) { rows[index] = updated }
                    else { rows.append(updated) }
                }
            }
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task { await recognize(item) }
            }
        }
    }

    private func summary(_ row: StockScreenshotRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(row.name.isEmpty ? row.symbol : row.name).fontWeight(.semibold)
                Spacer()
                Text(row.symbol).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }
            HStack {
                summaryValue("Shares", row.quantity)
                Spacer()
                summaryValue("Avg cost", row.cost)
                Spacer()
                summaryValue("Price", row.price)
            }
        }
        .contentShape(Rectangle())
    }

    private func summaryValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline).monospacedDigit()
        }
    }

    private func missingDetails(_ row: StockScreenshotRow) -> String {
        if row.positionType != "現股" { return "Margin and short positions aren’t supported" }
        var fields: [String] = []
        if row.normalizedSymbol.isEmpty { fields.append("stock name") }
        if StockScreenshotDraft.number(row.quantity) == nil { fields.append("shares") }
        if StockScreenshotDraft.number(row.cost) == nil { fields.append("average cost") }
        if (StockScreenshotDraft.number(row.price) ?? 0) <= 0 { fields.append("price") }
        return fields.isEmpty ? "Choose a valid stock" : "Missing " + fields.joined(separator: ", ")
    }

    private func loadStocks() async {
        guard !loadingStocks else { return }
        loadingStocks = true
        defer { loadingStocks = false }
        let market = await StockQuoteService.availableStocks()
        var bySymbol = Dictionary(market.map { ($0.symbol, $0) }, uniquingKeysWith: { first, _ in first })
        for holding in holdings where holding.currency == "TWD" && bySymbol[holding.symbol] == nil {
            bySymbol[holding.symbol] = StockIdentity(symbol: holding.symbol, name: holding.name)
        }
        stocks = bySymbol.values.sorted { $0.symbol < $1.symbol }
        resolveStockNames()
    }

    private func resolveStockNames() {
        for index in rows.indices where rows[index].symbol.isEmpty {
            if let stock = StockIdentity.exactName(rows[index].name, in: stocks) {
                rows[index].symbol = stock.symbol
                rows[index].name = stock.name
            }
        }
    }

    private func recognize(_ item: PhotosPickerItem) async {
        working = true
        message = nil
        rows = []
        recognizedText = ""
        imageData = nil
        defer { working = false; photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            message = "Could not read this image. Please choose it again."
            return
        }
        imageData = data
        do {
            let words = try await Task.detached { try StockScreenshotTable.recognize(data: data) }.value
            recognizedText = words.sorted { $0.box.midY > $1.box.midY }.map(\.text).joined(separator: " ")
            rows = StockScreenshotTable.rows(words)
            resolveStockNames()
            message = rows.isEmpty ? "No holdings table found. Include the column headers or add a position manually." : nil
        } catch { message = "Could not recognize text: \(error.localizedDescription)" }
    }

    private func save() {
        guard valid else { return }
        guard selected.allSatisfy({ row in holdings.filter { $0.currency == "TWD" && $0.symbol == row.normalizedSymbol }.count <= 1 }) else {
            message = "Multiple accounts hold the same ticker. Resolve the duplicate positions before importing."
            return
        }
        for row in selected {
            guard let quantity = StockScreenshotDraft.number(row.quantity), let cost = StockScreenshotDraft.number(row.cost), let price = StockScreenshotDraft.number(row.price) else { return }
            let existing = holdings.first { $0.symbol == row.normalizedSymbol && $0.currency == "TWD" }
            let holding = existing ?? StockHolding(id: StockScreenshotDraft.holdingID(symbol: row.normalizedSymbol), symbol: row.normalizedSymbol, name: row.name.isEmpty ? row.normalizedSymbol : row.name, quantity: 0, averageCostMinor: 0, currentPriceMinor: 0, currency: "TWD", linkedAccountId: nil)
            if existing == nil { context.insert(holding) }
            holding.quantity = quantity
            holding.averageCostMinor = Int((cost * 100).rounded())
            holding.currentPriceMinor = Int((price * 100).rounded())
            holding.priceAsOf = nil
            holding.dayChangeMinor = nil
            holding.updatedAt = ISO8601DateFormatter().string(from: Date())
            context.insert(PendingStockMutation(entityId: holding.id, entity: "stockHolding"))
        }
        do {
            try context.save()
            working = true
            Task {
                if session.isAuthenticated { await sync.refresh(context: context) }
                await StockQuoteService.refresh(context: context)
                dismiss()
            }
        } catch {
            context.rollback()
            message = "Could not save positions: \(error.localizedDescription)"
        }
    }
}

private struct StockImportRowEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var row: StockScreenshotRow
    let stocks: [StockIdentity]
    let save: (StockScreenshotRow) -> Void
    @State private var choosingStock = false
    @FocusState private var editingNumber: Bool

    var body: some View {
        NavigationStack {
            Form {
                if row.positionType != "現股" {
                    Section { Text("This is a margin or short position. Only cash stock holdings can be imported.") }
                }
                Section {
                    Button { choosingStock = true } label: {
                        LabeledContent("Stock", value: row.symbol.isEmpty ? "Choose by company name" : "\(row.name) · \(row.symbol)")
                    }
                    LabeledContent("Shares") { TextField("Quantity, not lots", text: $row.quantity).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($editingNumber) }
                    LabeledContent("Average cost") { TextField("Per share", text: $row.cost).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($editingNumber) }
                    LabeledContent("Market price") { TextField("Per share", text: $row.price).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($editingNumber) }
                }
            }
            .navigationTitle("Edit position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { row.included = true; save(row); dismiss() }.disabled(!row.valid)
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done typing") { editingNumber = false } }
            }
            .sheet(isPresented: $choosingStock) {
                StockNamePicker(stocks: stocks, initialQuery: row.name) { stock in
                    row.name = stock.name
                    row.symbol = stock.symbol
                }
            }
        }
    }
}

private struct StockNamePicker: View {
    let stocks: [StockIdentity]
    let initialQuery: String
    let select: (StockIdentity) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let matches = StockIdentity.search(query, in: stocks)
                if matches.isEmpty {
                    ContentUnavailableView.search(text: query)
                    Text("Try part of the company name. If the screenshot hides it, check the original brokerage page.")
                        .foregroundStyle(.secondary)
                }
                ForEach(matches) { stock in
                    Button {
                        select(stock)
                        dismiss()
                    } label: {
                        HStack {
                            Text(stock.name)
                            Spacer()
                            Text(stock.symbol).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Choose stock")
            .searchable(text: $query, prompt: "Company name or ticker")
            .onAppear { query = initialQuery }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
