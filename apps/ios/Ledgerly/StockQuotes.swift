import Foundation
import SwiftData

/// A daily closing price from the Taiwan exchanges.
struct StockQuote: Equatable, Sendable {
    let symbol: String
    let name: String
    let closeMinor: Int
    let changeMinor: Int?
    let date: Date
}

struct StockIdentity: Identifiable, Equatable, Sendable {
    let symbol: String
    let name: String
    var id: String { symbol }

    private static func normalized(_ text: String) -> String {
        text.filter { !$0.isWhitespace }.uppercased()
    }

    static func search(_ query: String, in stocks: [StockIdentity]) -> [StockIdentity] {
        let query = normalized(query)
        return stocks.filter { query.isEmpty || normalized($0.name).contains(query) || $0.symbol.contains(query) }
            .sorted { $0.symbol < $1.symbol }
    }

    static func exactName(_ name: String, in stocks: [StockIdentity]) -> StockIdentity? {
        guard !normalized(name).isEmpty else { return nil }
        let matches = stocks.filter { normalized($0.name) == normalized(name) }
        return matches.count == 1 ? matches[0] : nil
    }
}

/// Both feeds are public and free. Each lists the whole market, so fetching one never reveals what the user holds.
enum StockQuoteParser {
    private struct TWSERow: Decodable {
        let Date, Code, Name, ClosingPrice, Change: String
    }

    private struct TPExRow: Decodable {
        let Date, SecuritiesCompanyCode, CompanyName, Close, Change: String
    }

    static func twse(_ data: Data) throws -> [StockQuote] {
        try JSONDecoder().decode([TWSERow].self, from: data).compactMap {
            quote(symbol: $0.Code, name: $0.Name, close: $0.ClosingPrice, change: $0.Change, rocDate: $0.Date)
        }
    }

    static func tpex(_ data: Data) throws -> [StockQuote] {
        try JSONDecoder().decode([TPExRow].self, from: data).compactMap {
            quote(symbol: $0.SecuritiesCompanyCode, name: $0.CompanyName, close: $0.Close, change: $0.Change, rocDate: $0.Date)
        }
    }

    /// Rows without a trade that day list placeholders such as "" or "----" as the close, and are skipped.
    /// The change can also be text (e.g. 除息), which still leaves a usable close.
    private static func quote(symbol: String, name: String, close: String, change: String, rocDate: String) -> StockQuote? {
        guard let closeMinor = minorUnits(close), closeMinor > 0, let date = date(rocDate: rocDate) else { return nil }
        return StockQuote(symbol: symbol, name: name, closeMinor: closeMinor, changeMinor: minorUnits(change), date: date)
    }

    private static func minorUnits(_ text: String) -> Int? {
        guard let value = Double(text.replacingOccurrences(of: ",", with: "")) else { return nil }
        let minor = (value * 100).rounded()
        guard minor.isFinite, abs(value) <= 10_000_000, minor > Double(Int.min), minor < Double(Int.max) else { return nil }
        return Int(minor)
    }

    /// Republic of China calendar, e.g. "1151105" is 2026-11-05.
    private static func date(rocDate: String) -> Date? {
        guard rocDate.count == 7, let value = Int(rocDate) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        let year = value / 10_000 + 1911, month = value / 100 % 100, day = value % 100
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return date
    }
}

/// Keeps local holdings on the latest close. Prices stay on this device: the importer owns the synced
/// holding, and a sync that rewrites a holding clears its quote until the next `refresh` puts it back.
@MainActor
enum StockQuoteService {
    private static let fetchInterval: TimeInterval = 30 * 60
    private static var quotes: [String: StockQuote] = [:]
    private static var fetchedAt: Date?

    static func refresh(context: ModelContext) async {
        guard holdings(context).contains(where: { $0.isOpen && $0.currency == "TWD" }) else { return }
        if fetchedAt.map({ Date().timeIntervalSince($0) > fetchInterval }) ?? true { await fetch() }
        if apply(quotes, to: holdings(context)) { try? context.save() }
    }

    /// Reuses whole-market feeds; no stock name or screenshot is sent to the exchanges.
    static func availableStocks() async -> [StockIdentity] {
        if fetchedAt.map({ Date().timeIntervalSince($0) > fetchInterval }) ?? true { await fetch() }
        return quotes.values.map { StockIdentity(symbol: $0.symbol, name: $0.name) }
            .sorted { $0.symbol < $1.symbol }
    }

    /// Returns whether anything changed.
    @discardableResult
    static func apply(_ quotes: [String: StockQuote], to holdings: [StockHolding]) -> Bool {
        var changed = false
        for holding in holdings where holding.currency == "TWD" {
            guard let quote = quotes[holding.symbol] else { continue }
            if let currentDate = holding.priceAsOf, quote.date < currentDate { continue }
            if holding.currentPriceMinor != quote.closeMinor || holding.dayChangeMinor != quote.changeMinor || holding.priceAsOf != quote.date {
                holding.currentPriceMinor = quote.closeMinor
                holding.dayChangeMinor = quote.changeMinor
                holding.priceAsOf = quote.date
                changed = true
            }
            // The importer only knows the ticker, so it uses that as the name.
            if holding.name == holding.symbol, !quote.name.isEmpty {
                holding.name = quote.name
                changed = true
            }
        }
        return changed
    }

    private static func holdings(_ context: ModelContext) -> [StockHolding] {
        (try? context.fetch(FetchDescriptor<StockHolding>())) ?? []
    }

    private static func fetch() async {
        async let listed = load("https://openapi.twse.com.tw/v1/exchangeReport/STOCK_DAY_ALL", StockQuoteParser.twse)
        async let otc = load("https://www.tpex.org.tw/openapi/v1/tpex_mainboard_quotes", StockQuoteParser.tpex)
        let results = await [listed, otc]
        for quote in results.compactMap({ $0 }).joined() { quotes[quote.symbol] = quote }
        // A failed feed is retried on the next refresh instead of waiting out the interval.
        if results.allSatisfy({ $0 != nil }) { fetchedAt = Date() }
    }

    private static func load(_ url: String, _ parse: @Sendable (Data) throws -> [StockQuote]) async -> [StockQuote]? {
        guard let url = URL(string: url) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return try parse(data)
        } catch {
            NSLog("Stock quote refresh failed for %@: %@", url.absoluteString, error.localizedDescription)
            return nil
        }
    }
}
