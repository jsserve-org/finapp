import Foundation
import Photos
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
    case disabled
    case permissionDenied
    case noScreenshot
    case alreadyImported
    case accountMissing
    case amountNotFound

    var message: String {
        switch self {
        case .imported(let payment): "Imported \(payment.title)."
        case .disabled: "Screenshot Sync is off."
        case .permissionDenied: "Allow photo access in Settings to use Screenshot Sync."
        case .noScreenshot: "No screenshot was found."
        case .alreadyImported: "The latest screenshot was already imported."
        case .accountMissing: "Choose an account for Screenshot Sync."
        case .amountNotFound: "No payment amount was found in the latest screenshot."
        }
    }
}

@MainActor
final class ScreenshotSyncService {
    static let shared = ScreenshotSyncService()

    static let enabledKey = "ledgerly.screenshotSync.enabled"
    static let accountIDKey = "ledgerly.screenshotSync.accountID"
    private static let enabledAtKey = "ledgerly.screenshotSync.enabledAt"
    private static let lastAssetIDKey = "ledgerly.screenshotSync.lastAssetID"
    private static let lastMessageKey = "ledgerly.screenshotSync.lastMessage"

    private var isImporting = false

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var accountID: String { UserDefaults.standard.string(forKey: accountIDKey) ?? "" }
    static var lastMessage: String? { UserDefaults.standard.string(forKey: lastMessageKey) }

    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled else {
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            return false
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let allowed = status == .authorized
        UserDefaults.standard.set(allowed, forKey: Self.enabledKey)
        if allowed { UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.enabledAtKey) }
        return allowed
    }

    func importLatest(context: ModelContext, force: Bool = false) async -> ScreenshotSyncResult {
        guard Self.isEnabled || force else { return .disabled }
        guard !isImporting else { return .alreadyImported }
        isImporting = true
        defer { isImporting = false }

        let authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard authorization == .authorized else { return finish(.permissionDenied) }
        guard !Self.accountID.isEmpty,
              let account = try? context.fetch(FetchDescriptor<CachedAccount>()).first(where: { $0.id == Self.accountID }) else {
            return finish(.accountMissing)
        }
        guard let asset = newestScreenshot() else { return finish(.noScreenshot) }
        if asset.localIdentifier == UserDefaults.standard.string(forKey: Self.lastAssetIDKey) { return .alreadyImported }

        let enabledAt = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.enabledAtKey))
        if !force, let created = asset.creationDate, created < enabledAt { return .alreadyImported }
        guard let image = image(for: asset) else { return finish(.noScreenshot, assetID: asset.localIdentifier) }
        let lines = recognizedLines(in: image)
        guard let payment = ScreenshotPaymentParser.parse(lines: lines, currency: account.currency) else {
            return finish(.amountNotFound, assetID: asset.localIdentifier)
        }

        let timestamp = ISO8601DateFormatter().string(from: asset.creationDate ?? Date())
        let transaction = CachedTransaction(dto: TransactionDTO(
            id: UUID().uuidString.lowercased(), accountId: account.id, description: payment.title,
            amount: Money(amountMinor: -payment.amountMinor, currency: account.currency), bookedAt: timestamp,
            pending: false, category: "Screenshot Sync", updatedAt: timestamp
        ), initialVersion: 0)
        context.insert(transaction)
        context.insert(PendingTransactionCreate(entityId: transaction.id))
        account.amountMinor -= payment.amountMinor
        account.updatedAt = ISO8601DateFormatter().string(from: Date())
        context.insert(PendingAccountMutation(entityId: account.id))
        try? context.save()
        return finish(.imported(payment), assetID: asset.localIdentifier)
    }

    private func finish(_ result: ScreenshotSyncResult, assetID: String? = nil) -> ScreenshotSyncResult {
        if let assetID { UserDefaults.standard.set(assetID, forKey: Self.lastAssetIDKey) }
        UserDefaults.standard.set(result.message, forKey: Self.lastMessageKey)
        return result
    }

    private func newestScreenshot() -> PHAsset? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 30
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        for index in 0..<assets.count {
            let asset = assets.object(at: index)
            if asset.mediaSubtypes.contains(.photoScreenshot) { return asset }
        }
        return nil
    }

    private func image(for asset: PHAsset) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { image, _ in
            result = image?.cgImage
        }
        return result
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
