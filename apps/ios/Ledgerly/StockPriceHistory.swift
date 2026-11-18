import Charts
import Foundation
import SwiftUI

struct StockPricePoint: Identifiable, Equatable, Sendable {
    let date: Date
    let price: Double
    var id: Date { date }
}

enum StockHistoryRange: String, CaseIterable, Identifiable {
    case week = "1W", month = "1M", quarter = "3M", half = "6M", year = "1Y"
    var id: Self { self }
    func start(now: Date, calendar: Calendar) -> Date {
        if self == .week { return calendar.date(byAdding: .day, value: -7, to: now)! }
        let months = self == .month ? 1 : self == .quarter ? 3 : self == .half ? 6 : 12
        return calendar.date(byAdding: .month, value: -months, to: now)!
    }
}

enum StockHistoryParser {
    private struct Table: Decodable { let fields: [String]; let data: [[String]] }
    private struct Response: Decodable {
        let fields: [String]?
        let data: [[String]]?
        let tables: [Table]?
    }
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }

    static func parse(_ data: Data) throws -> [StockPricePoint] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let tables = response.tables ?? [Table(fields: response.fields ?? [], data: response.data ?? [])]
        return tables.flatMap { table -> [StockPricePoint] in
            let fields = table.fields.map { $0.filter { !$0.isWhitespace } }
            guard let dateIndex = fields.firstIndex(of: "日期"),
                  let priceIndex = fields.firstIndex(where: { ["收盤價", "收盤"].contains($0) }) else { return [] }
            return table.data.compactMap { row in
                guard row.count > max(dateIndex, priceIndex),
                      let price = Double(row[priceIndex].replacingOccurrences(of: ",", with: "")),
                      price.isFinite, price > 0, price <= 10_000_000 else { return nil }
                let tokens = row[dateIndex].split(separator: "/", omittingEmptySubsequences: false)
                guard tokens.count == 3 else { return nil }
                let parts = tokens.compactMap { Int($0) }
                guard parts.count == 3 else { return nil }
                let year = parts[0] < 1911 ? parts[0] + 1911 : parts[0]
                let components = DateComponents(year: year, month: parts[1], day: parts[2], hour: 12)
                guard let date = calendar.date(from: components),
                      calendar.component(.year, from: date) == year,
                      calendar.component(.month, from: date) == parts[1], calendar.component(.day, from: date) == parts[2] else { return nil }
                return StockPricePoint(date: date, price: price)
            }
        }.sorted { $0.date < $1.date }
    }
}

actor StockHistoryService {
    static let shared = StockHistoryService()
    private struct Cached { let points: [StockPricePoint]; let fetched: Date }
    private var cache: [String: Cached] = [:]
    private var otc: [String: Bool] = [:]

    func load(symbol: String, range: StockHistoryRange, now: Date = Date()) async throws -> [StockPricePoint] {
        guard symbol.range(of: #"^[0-9A-Z]{4,6}$"#, options: .regularExpression) != nil else { return [] }
        let calendar = StockHistoryParser.calendar
        let start = range.start(now: now, calendar: calendar)
        var month = calendar.date(from: calendar.dateComponents([.year, .month], from: start))!
        var points: [StockPricePoint] = []
        while month <= now {
            try Task.checkCancellation()
            let year = calendar.component(.year, from: month), number = calendar.component(.month, from: month)
            let key = "\(symbol)-\(year)-\(number)"
            if let cached = cache[key], now.timeIntervalSince(cached.fetched) < 1800 {
                points += cached.points
            } else {
                var monthly = try await fetch(symbol: symbol, year: year, month: number, otc: otc[symbol] ?? false)
                if monthly.isEmpty && otc[symbol] == nil {
                    monthly = try await fetch(symbol: symbol, year: year, month: number, otc: true)
                    if !monthly.isEmpty { otc[symbol] = true }
                } else if !monthly.isEmpty && otc[symbol] == nil { otc[symbol] = false }
                cache[key] = Cached(points: monthly, fetched: now)
                points += monthly
            }
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }
        let unique = Dictionary(points.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        return unique.values.filter { $0.date >= calendar.startOfDay(for: start) && $0.date <= now }.sorted { $0.date < $1.date }
    }

    private func fetch(symbol: String, year: Int, month: Int, otc: Bool) async throws -> [StockPricePoint] {
        var url = URLComponents(string: otc ? "https://www.tpex.org.tw/www/zh-tw/afterTrading/tradingStock" : "https://www.twse.com.tw/rwd/zh/afterTrading/STOCK_DAY")!
        url.queryItems = [URLQueryItem(name: "response", value: "json"),
                          URLQueryItem(name: otc ? "code" : "stockNo", value: symbol),
                          URLQueryItem(name: "date", value: otc ? String(format: "%04d/%02d/01", year, month) : String(format: "%04d%02d01", year, month))]
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url.url!, timeoutInterval: 20))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try StockHistoryParser.parse(data)
    }
}

struct StockHistoryChart: View {
    let symbol: String
    let currency: String
    @State private var range = StockHistoryRange.month
    @State private var points: [StockPricePoint] = []
    @State private var selectedDate: Date?
    @State private var loading = false
    @State private var error: String?
    @State private var retry = 0

    private var selected: StockPricePoint? {
        guard let selectedDate else { return points.last }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var color: Color { (points.last?.price ?? 0) >= (points.first?.price ?? 0) ? .green : .red }
    private var domain: ClosedRange<Double> {
        let low = points.map(\.price).min() ?? 0, high = points.map(\.price).max() ?? 1
        let padding = max((high - low) * 0.15, high * 0.005, 0.01)
        return max(0, low - padding)...(high + padding)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selected.map { $0.price.formatted(.currency(code: currency).presentation(.isoCode)) } ?? "—")
                        .font(.system(.title, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text(selected.map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "Price history")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let first = points.first, let displayed = selected {
                    Text(((displayed.price - first.price) / first.price).formatted(.percent.precision(.fractionLength(2)).sign(strategy: .always())))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(displayed.price >= first.price ? Color.green : .red).monospacedDigit()
                }
            }
            HStack {
                ForEach(StockHistoryRange.allCases) { option in
                    Button { range = option } label: {
                        Text(option.rawValue).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .background(range == option ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(range == option ? .isSelected : [])
                }
            }
            if loading {
                ProgressView("Loading prices…").frame(maxWidth: .infinity).frame(height: 230)
            } else if let error {
                VStack(spacing: 12) {
                    Text(error).font(.subheadline).foregroundStyle(.secondary)
                    Button("Retry") { retry += 1 }
                }.frame(maxWidth: .infinity).frame(height: 230)
            } else if points.count < 2 {
                ContentUnavailableView("No price history", systemImage: "chart.xyaxis.line", description: Text("Try a longer range."))
                    .frame(height: 230)
            } else {
                Chart {
                    ForEach(points) { point in
                        AreaMark(x: .value("Date", point.date), yStart: .value("Base", domain.lowerBound), yEnd: .value("Close", point.price))
                            .foregroundStyle(LinearGradient(colors: [color.opacity(0.30), color.opacity(0.01)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", point.date), y: .value("Close", point.price))
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if let first = points.first {
                        RuleMark(y: .value("First close", first.price)).foregroundStyle(.secondary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    if selectedDate != nil, let selected {
                        RuleMark(x: .value("Selected", selected.date)).foregroundStyle(.secondary.opacity(0.5))
                        PointMark(x: .value("Date", selected.date), y: .value("Close", selected.price)).foregroundStyle(color).symbolSize(45)
                    }
                }
                .chartYScale(domain: domain)
                .chartXSelection(value: $selectedDate)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(.secondary.opacity(0.12)); AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(.secondary.opacity(0.12)); AxisValueLabel() } }
                .chartLegend(.hidden).frame(height: 230)
                .accessibilityLabel("\(symbol) daily closing prices. Drag to inspect a date.")
            }
            Text("Daily close · TWSE / TPEx · Unadjusted").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .task(id: "\(symbol)-\(range.rawValue)-\(retry)") {
            loading = true; selectedDate = nil; points = []; error = nil
            do {
                let values = try await StockHistoryService.shared.load(symbol: symbol, range: range)
                try Task.checkCancellation()
                points = values
            } catch {
                guard !Task.isCancelled else { return }
                self.error = "Price history couldn’t load. Try again."
            }
            loading = false
        }
    }
}
