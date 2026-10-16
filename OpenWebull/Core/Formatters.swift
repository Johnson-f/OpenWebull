import Foundation

enum Format {
    private static let priceFormatter = makeDecimal(fractionDigits: 2)
    private static let integerFormatter = makeDecimal(fractionDigits: 0)

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter
    }()

    private static func makeDecimal(fractionDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        return formatter
    }

    static func price(_ value: Double) -> String {
        priceFormatter.string(from: NSNumber(value: value)) ?? "--"
    }

    /// Chart and quote style: three decimals below $10, two above.
    static func legendPrice(_ value: Double) -> String {
        abs(value) < 10 ? String(format: "%.3f", value) : price(value)
    }

    static func signedLegendPrice(_ value: Double) -> String {
        (value > 0 ? "+" : "") + legendPrice(value)
    }

    static func easternTimestamp(_ date: Date) -> String {
        easternFormatter.string(from: date)
    }

    private static let easternFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        return formatter
    }()

    static func signedPrice(_ value: Double) -> String {
        (value > 0 ? "+" : "") + price(value)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%@%.2f%%", fraction > 0 ? "+" : "", fraction * 100)
    }

    static func currency(_ value: Double) -> String {
        (value < 0 ? "-$" : "$") + price(abs(value))
    }

    static func signedCurrency(_ value: Double) -> String {
        (value > 0 ? "+" : "") + currency(value)
    }

    static func integer(_ value: Int) -> String {
        integerFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Abbreviates large quantities the way market data terminals do: 1.23K, 4.56M, 7.89B.
    static func compact(_ value: Double) -> String {
        let magnitude = abs(value)
        switch magnitude {
        case 1e12...: return String(format: "%.2fT", value / 1e12)
        case 1e9...: return String(format: "%.2fB", value / 1e9)
        case 1e6...: return String(format: "%.2fM", value / 1e6)
        case 1e4...: return String(format: "%.2fK", value / 1e3)
        default: return integer(Int(value.rounded()))
        }
    }

    static func clock(_ date: Date) -> String {
        clockFormatter.string(from: date)
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func mediumDate(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()

    static func dateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }
}
