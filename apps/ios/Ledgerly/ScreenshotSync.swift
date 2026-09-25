import Foundation
import SwiftData
import UIKit
import Vision

struct ScreenshotPayment: Equatable {
    let amountMinor: Int
    let title: String
}

enum ScreenshotPaymentParser {
    private static let amountWords = ["amount", "total", "paid", "payment", "purchase", "金額", "付款", "支付", "消費", "交易金額", "扣款"]
    private static let balanceWords = ["balance", "available", "餘額", "可用", "帳戶總覽", "account balance"]
    private static let ignoredTitleWords = amountWords + balanceWords + ["successful", "completed", "成功", "完成", "receipt", "收據"]

    static func parse(lines: [String], currency: String) -> ScreenshotPayment? {
        let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let candidates = cleaned.enumerated().compactMap { index, line -> (index: Int, value: Decimal, score: Int)? in
            guard let value = decimalAmount(in: line), value > 0 else { return nil }
            let lower = line.lowercased()
            let nearbyRange = max(0, index - 2)...min(cleaned.count - 1, index + 2)
            let nearby = nearbyRange.map { cleaned[$0].lowercased() }.joined(separator: " ")
            var score = 0
            if amountWords.contains(where: lower.contains) { score += 8 }
            else if amountWords.contains(where: nearby.contains) { score += 4 }
            if currencyMarkers(currency).contains(where: lower.contains) { score += 5 }
            if balanceWords.contains(where: nearby.contains) { score -= 12 }
            if line.rangeOfCharacter(from: .letters) == nil { score += 1 }
            return (index, value, score)
        }
        guard let best = candidates.max(by: { lhs, rhs in
            lhs.score == rhs.score ? lhs.index > rhs.index : lhs.score < rhs.score
        }), best.score >= 5 else { return nil }

        let minor = NSDecimalNumber(decimal: best.value * 100).intValue
        guard minor > 0 else { return nil }
        return ScreenshotPayment(amountMinor: minor, title: title(near: best.index, lines: cleaned))
    }

    private static func currencyMarkers(_ currency: String) -> [String] {
        switch currency {
        case "TWD": ["twd", "nt$", "ntd", "新台幣"]
        case "USD": ["usd", "us$", "$ "]
        case "JPY": ["jpy", "¥", "円"]
        case "PHP": ["php", "₱"]
        case "EUR": ["eur", "€"]
        case "GBP": ["gbp", "£"]
        default: [currency.lowercased()]
        }
    }

    private static func decimalAmount(in line: String) -> Decimal? {
        let pattern = #"(?:TWD|NTD|NT\$|USD|US\$|JPY|PHP|EUR|GBP|[$¥₱€£])?\s*([0-9][0-9,. ]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, range: range)
        return matches.compactMap { match -> Decimal? in
            guard let valueRange = Range(match.range(at: 1), in: line) else { return nil }
            return normalizedDecimal(String(line[valueRange]))
        }.max()
    }

    private static func normalizedDecimal(_ value: String) -> Decimal? {
        var normalized = value.replacingOccurrences(of: " ", with: "")
        let comma = normalized.lastIndex(of: ",")
        let dot = normalized.lastIndex(of: ".")
        if comma != nil, dot != nil {
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        } else if let comma {
            let digitsAfter = normalized.distance(from: normalized.index(after: comma), to: normalized.endIndex)
            normalized = digitsAfter == 2
                ? normalized.replacingOccurrences(of: ",", with: ".")
                : normalized.replacingOccurrences(of: ",", with: "")
        }
        return Decimal(string: normalized)
    }

    private static func title(near amountIndex: Int, lines: [String]) -> String {
        let nearby = [amountIndex - 1, amountIndex + 1, amountIndex - 2, amountIndex + 2]
        for index in nearby where lines.indices.contains(index) {
            let line = lines[index]
            let lower = line.lowercased()
            let digitCount = line.filter(\.isNumber).count
            if line.count >= 2, line.count <= 60, digitCount < max(4, line.count / 2), !ignoredTitleWords.contains(where: lower.contains) {
                return line
            }
        }
        return "Screenshot payment"
    }
}

enum ScreenshotSyncResult: Equatable {
    case imported(ScreenshotPayment)
    case alreadyImported
    case accountMissing
    case unreadableImage
    case amountNotFound

    var message: String {
        switch self {
        case .imported(let payment): "Imported \(payment.title)."
        case .alreadyImported: "That screenshot was already imported."
        case .accountMissing: "Choose an account for Screenshot Sync."
        case .unreadableImage: "That image could not be read."
        case .amountNotFound: "No payment amount was found in that screenshot."
        }
    }
}

@MainActor
final class ScreenshotSyncService {
    static let shared = ScreenshotSyncService()

    static let accountIDKey = "ledgerly.screenshotSync.accountID"
    private static let lastAssetIDKey = "ledgerly.screenshotSync.lastAssetID"
    private static let importedAssetIDsKey = "ledgerly.screenshotSync.importedAssetIDs"
    private static let lastMessageKey = "ledgerly.screenshotSync.lastMessage"

    private var isImporting = false

    static var accountID: String { UserDefaults.standard.string(forKey: accountIDKey) ?? "" }
    static var lastMessage: String? { UserDefaults.standard.string(forKey: lastMessageKey) }

    func importImageData(_ data: Data, assetID: String?, context: ModelContext) async -> ScreenshotSyncResult {
        guard !isImporting else { return .alreadyImported }
        isImporting = true
        defer { isImporting = false }

        guard !Self.accountID.isEmpty,
              let account = try? context.fetch(FetchDescriptor<CachedAccount>()).first(where: { $0.id == Self.accountID }) else {
            return finish(.accountMissing)
        }
        if let assetID, importedAssetIDs().contains(assetID) { return .alreadyImported }
        guard let image = UIImage(data: data)?.cgImage else { return finish(.unreadableImage, assetID: assetID) }
        let lines = recognizedLines(in: image)
        guard let payment = ScreenshotPaymentParser.parse(lines: lines, currency: account.currency) else {
            return finish(.amountNotFound, assetID: assetID)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let transaction = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(), accountId: account.id, description: payment.title,
            amount: Money(amountMinor: -payment.amountMinor, currency: account.currency), bookedAt: timestamp,
            pending: false, category: "Screenshot Sync", source: "screenshot", updatedAt: timestamp
        ), initialVersion: 0)
        context.insert(transaction)
        context.insert(PendingTransactionCreate(entityId: transaction.id))
        let recurringPayments = (try? context.fetch(FetchDescriptor<RecurringPayment>())) ?? []
        autoLinkRecurringPayment(transaction, payments: recurringPayments, context: context)
        account.amountMinor -= payment.amountMinor
        account.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        return finish(.imported(payment), assetID: assetID)
    }

    private func finish(_ result: ScreenshotSyncResult, assetID: String? = nil) -> ScreenshotSyncResult {
        if case .imported = result, let assetID {
            var ids = importedAssetIDs()
            ids.removeAll { $0 == assetID }
            ids.append(assetID)
            UserDefaults.standard.set(Array(ids.suffix(100)), forKey: Self.importedAssetIDsKey)
            UserDefaults.standard.set(assetID, forKey: Self.lastAssetIDKey)
        }
        UserDefaults.standard.set(result.message, forKey: Self.lastMessageKey)
        return result
    }

    private func importedAssetIDs() -> [String] {
        var ids = UserDefaults.standard.stringArray(forKey: Self.importedAssetIDsKey) ?? []
        if let legacy = UserDefaults.standard.string(forKey: Self.lastAssetIDKey), !ids.contains(legacy) { ids.append(legacy) }
        return ids
    }

    private func recognizedLines(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "zh-Hant"]
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
