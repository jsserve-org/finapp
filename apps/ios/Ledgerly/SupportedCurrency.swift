import Foundation

struct SupportedCurrency: Identifiable, Hashable {
    let code: String
    let name: String

    var id: String { code }

    static let all = [
        SupportedCurrency(code: "TWD", name: "New Taiwan dollar"),
        SupportedCurrency(code: "USD", name: "US dollar"),
        SupportedCurrency(code: "JPY", name: "Japanese yen"),
        SupportedCurrency(code: "PHP", name: "Philippine peso"),
        SupportedCurrency(code: "EUR", name: "Euro"),
        SupportedCurrency(code: "GBP", name: "British pound"),
        SupportedCurrency(code: "CNY", name: "Chinese yuan"),
        SupportedCurrency(code: "HKD", name: "Hong Kong dollar"),
        SupportedCurrency(code: "SGD", name: "Singapore dollar"),
        SupportedCurrency(code: "KRW", name: "South Korean won"),
        SupportedCurrency(code: "AUD", name: "Australian dollar"),
        SupportedCurrency(code: "CAD", name: "Canadian dollar"),
        SupportedCurrency(code: "THB", name: "Thai baht"),
        SupportedCurrency(code: "MYR", name: "Malaysian ringgit"),
        SupportedCurrency(code: "VND", name: "Vietnamese dong"),
        SupportedCurrency(code: "INR", name: "Indian rupee"),
        SupportedCurrency(code: "IDR", name: "Indonesian rupiah")
    ]

    static var defaultCode: String {
        let localCode = Locale.current.currency?.identifier
        return all.contains(where: { $0.code == localCode }) ? localCode ?? "USD" : "USD"
    }
}
