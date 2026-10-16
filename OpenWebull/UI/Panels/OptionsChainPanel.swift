import AppKit

/// Calls on the left, strikes in the middle, puts on the right, priced with Black–Scholes.
final class OptionsChainPanel: PanelViewController {
    private var expirationPicker: NSPopUpButton!
    private var spotLabel: NSTextField!
    private var table: DataTableView!
    private var expirations: [Date] = []
    private var rows: [OptionChainRow] = []
    private var spot = 0.0
    private var refreshCounter = 0

    private static let callColumns = ["cBid", "cAsk", "cLast", "cVol", "cOI", "cIV", "cDelta"]
    private static let putColumns = ["pDelta", "pIV", "pOI", "pVol", "pLast", "pBid", "pAsk"]
    private static let titles = [
        "cBid": "Bid", "cAsk": "Ask", "cLast": "Last", "cVol": "Volume", "cOI": "Open Int", "cIV": "IV", "cDelta": "Delta",
        "pBid": "Bid", "pAsk": "Ask", "pLast": "Last", "pVol": "Volume", "pOI": "Open Int", "pIV": "IV", "pDelta": "Delta",
    ]

    init(env: AppEnvironment) {
        super.init(env: env, title: "Options")
    }

    override func buildContent() {
        expirations = OptionChainBuilder.expirations(from: Date())
        expirationPicker = .make(items: expirations.map(expirationTitle), target: self, action: #selector(expirationChanged))
        spotLabel = .label(font: Theme.numberFont(12), color: Theme.textSecondary)
        let callsLabel = NSTextField.label("CALLS", font: Theme.font(11, .bold), color: Theme.up)
        let putsLabel = NSTextField.label("PUTS", font: Theme.font(11, .bold), color: Theme.down)

        let columns = Self.callColumns.map { TableColumnSpec(id: $0, title: Self.titles[$0]!, width: 62) }
            + [TableColumnSpec(id: "strike", title: "Strike", width: 76, alignment: .center)]
            + Self.putColumns.map { TableColumnSpec(id: $0, title: Self.titles[$0]!, width: 62) }
        table = DataTableView(columns: columns, rowHeight: 22)
        table.rowCount = { [unowned self] in rows.count }
        table.content = { [unowned self] row, column in cell(row: row, column: column) }

        view.addSubviews(expirationPicker, spotLabel, callsLabel, putsLabel, table)
        NSLayoutConstraint.activate([
            expirationPicker.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            expirationPicker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            spotLabel.centerYAnchor.constraint(equalTo: expirationPicker.centerYAnchor),
            spotLabel.leadingAnchor.constraint(equalTo: expirationPicker.trailingAnchor, constant: 14),
            callsLabel.topAnchor.constraint(equalTo: expirationPicker.bottomAnchor, constant: 6),
            callsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            putsLabel.centerYAnchor.constraint(equalTo: callsLabel.centerYAnchor),
            putsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            table.topAnchor.constraint(equalTo: callsLabel.bottomAnchor, constant: 4),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Re-pricing every half second is wasteful; every few ticks keeps it feeling live.
    override func marketDidTick() {
        refreshCounter += 1
        if refreshCounter % 4 == 0 { refresh() }
    }

    override func refresh() {
        guard let instrument = env.market.instrument(linkedSymbol), let quote = env.market.quote(for: linkedSymbol) else { return }
        guard instrument.isTradable else {
            rows = []
            spotLabel.stringValue = "Options are not listed for indices in the simulator."
            table.tableView.reloadData()
            return
        }
        let expiration = expirations[max(expirationPicker.indexOfSelectedItem, 0)]
        let previousCount = rows.count
        spot = quote.last
        rows = OptionChainBuilder.chain(for: instrument, spot: spot, expiration: expiration, now: Date())
        let days = Int(ceil(expiration.timeIntervalSinceNow / 86_400))
        spotLabel.stringValue = "\(instrument.symbol) \(Format.price(spot)) · \(days)D to expiry"
        if previousCount == rows.count {
            table.refresh()
        } else {
            table.tableView.reloadData()
            if let atm = rows.indices.min(by: { abs(rows[$0].strike - spot) < abs(rows[$1].strike - spot) }) {
                table.tableView.scrollRowToVisible(min(atm + 6, rows.count - 1))
                table.tableView.scrollRowToVisible(max(atm - 6, 0))
            }
        }
    }

    override func linkedSymbolDidChange(_ symbol: String) {
        rows = []
        refresh()
    }

    private func cell(row: Int, column: String) -> CellContent {
        let chainRow = rows[row]
        if column == "strike" {
            return CellContent(text: Format.price(chainRow.strike), font: Theme.numberFont(12, .semibold), background: Theme.raisedBackground)
        }
        let isCall = column.hasPrefix("c")
        let contract = isCall ? chainRow.call : chainRow.put
        let inTheMoney = isCall ? chainRow.strike < spot : chainRow.strike > spot
        var content: CellContent
        switch column.dropFirst() {
        case "Bid": content = .number(Format.price(contract.bid))
        case "Ask": content = .number(Format.price(contract.ask))
        case "Last": content = .number(Format.price(contract.last))
        case "Vol": content = .number(Format.compact(Double(contract.volume)), color: Theme.textSecondary)
        case "OI": content = .number(Format.compact(Double(contract.openInterest)), color: Theme.textSecondary)
        case "IV": content = .number(String(format: "%.1f%%", contract.impliedVolatility * 100), color: Theme.textSecondary)
        case "Delta": content = .number(String(format: "%.3f", abs(contract.delta) < 0.0005 ? 0 : contract.delta), color: isCall ? Theme.up : Theme.down)
        default: content = .text("")
        }
        if inTheMoney {
            content.background = Theme.accent.withAlphaComponent(0.08)
        }
        return content
    }

    private func expirationTitle(_ date: Date) -> String {
        let days = Int(ceil(date.timeIntervalSinceNow / 86_400))
        return "\(Format.shortDate(date)) (\(days)D)"
    }

    @objc private func expirationChanged() {
        rows = []
        refresh()
    }
}
