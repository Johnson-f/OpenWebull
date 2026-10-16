import AppKit

/// Symbol, last price and the key session statistics for the linked instrument.
final class QuoteHeaderView: FillView {
    private let symbolLabel = NSTextField.label(font: Theme.font(18, .bold))
    private let nameLabel = NSTextField.label(font: Theme.font(12), color: Theme.textSecondary)
    private let priceLabel = NSTextField.label(font: Theme.numberFont(26, .semibold))
    private let changeLabel = NSTextField.label(font: Theme.numberFont(13, .medium))
    private let timeLabel = NSTextField.label(font: Theme.font(11), color: Theme.textTertiary)
    private var statValues: [String: NSTextField] = [:]

    private static let statColumns = [
        ["Open", "Bid"], ["High", "Ask"], ["Low", "Mkt Cap"], ["Prev Close", "P/E"], ["Volume", "Turnover"],
    ]

    init() {
        super.init(color: Theme.panelBackground)
        borderEdges = [.bottom]

        let identity = NSStackView(views: [symbolLabel, nameLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 2

        let priceStack = NSStackView(views: [priceLabel, changeLabel, timeLabel])
        priceStack.orientation = .vertical
        priceStack.alignment = .leading
        priceStack.spacing = 0

        let columns = Self.statColumns.map { keys -> NSStackView in
            let column = NSStackView(views: keys.map(makeStatCell))
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 6
            column.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
            return column
        }
        let grid = NSStackView(views: columns)
        grid.spacing = 18
        grid.alignment = .top
        grid.setHuggingPriority(.required, for: .horizontal)
        for column in columns.suffix(2) {
            grid.setVisibilityPriority(.detachOnlyIfNecessary, for: column)
        }
        priceLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        changeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        addSubviews(identity, priceStack, grid)
        NSLayoutConstraint.activate([
            identity.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            identity.centerYAnchor.constraint(equalTo: centerYAnchor),
            identity.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            priceStack.leadingAnchor.constraint(equalTo: identity.trailingAnchor, constant: 24),
            priceStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            grid.leadingAnchor.constraint(greaterThanOrEqualTo: priceStack.trailingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            grid.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 84),
        ])
        symbolLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func makeStatCell(_ key: String) -> NSView {
        let value = NSTextField.label("--", font: Theme.numberFont(12))
        statValues[key] = value
        let cell = NSStackView(views: [NSTextField.label(key, font: Theme.font(10.5), color: Theme.textSecondary), value])
        cell.orientation = .vertical
        cell.alignment = .leading
        cell.spacing = 1
        return cell
    }

    func update(instrument: Instrument, quote: Quote) {
        symbolLabel.stringValue = instrument.symbol
        nameLabel.stringValue = "\(instrument.name) · \(instrument.exchange)"
        priceLabel.stringValue = Format.price(quote.last)
        let trend = Theme.trendColor(quote.change)
        priceLabel.textColor = trend
        changeLabel.stringValue = "\(Format.signedPrice(quote.change))  \(Format.percent(quote.changePercent))"
        changeLabel.textColor = trend
        timeLabel.stringValue = Format.clock(quote.updatedAt)

        let marketCap = instrument.kind == .stock ? Format.compact(instrument.sharesOutstanding * quote.last) : "--"
        let earnings = instrument.earningsPerShare
        let values: [String: String] = [
            "Open": Format.price(quote.open),
            "High": Format.price(quote.high),
            "Low": Format.price(quote.low),
            "Prev Close": Format.price(quote.previousClose),
            "Volume": instrument.isTradable ? Format.compact(quote.volume) : "--",
            "Bid": instrument.isTradable ? Format.price(quote.bid) : "--",
            "Ask": instrument.isTradable ? Format.price(quote.ask) : "--",
            "Mkt Cap": marketCap,
            "P/E": earnings > 0 ? String(format: "%.1f", quote.last / earnings) : "--",
            "Turnover": instrument.isTradable ? Format.compact(quote.volume * quote.last) : "--",
        ]
        for (key, value) in values {
            statValues[key]?.stringValue = value
        }
        statValues["High"]?.textColor = Theme.trendColor(quote.high - quote.previousClose)
        statValues["Low"]?.textColor = Theme.trendColor(quote.low - quote.previousClose)
        statValues["Open"]?.textColor = Theme.trendColor(quote.open - quote.previousClose)
    }
}
