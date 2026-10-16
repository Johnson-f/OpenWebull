import AppKit

final class ScreenerPanel: PanelViewController {
    private struct Criteria {
        var sector: String?
        var kind: Instrument.Kind?
        var minimumPrice: Double?
        var maximumPrice: Double?
        var minimumChange: Double?
        var minimumMarketCap: Double?

        func matches(_ instrument: Instrument, _ quote: Quote) -> Bool {
            if let sector, instrument.sector != sector { return false }
            if let kind, instrument.kind != kind { return false }
            if let minimumPrice, quote.last < minimumPrice { return false }
            if let maximumPrice, quote.last > maximumPrice { return false }
            if let minimumChange, quote.changePercent < minimumChange { return false }
            if let minimumMarketCap, instrument.sharesOutstanding * quote.last < minimumMarketCap { return false }
            return true
        }
    }

    private static let marketCapOptions: [(String, Double?)] = [("Any Market Cap", nil), ("> $10B", 10e9), ("> $100B", 100e9), ("> $1T", 1e12)]
    private static let changeOptions: [(String, Double?)] = [("Any Change", nil), ("Up today", 0.000001), ("> +1%", 0.01), ("> +2%", 0.02), ("Down > 1%", nil)]

    private var sectorPicker: NSPopUpButton!
    private var kindPicker: NSPopUpButton!
    private var capPicker: NSPopUpButton!
    private var changePicker: NSPopUpButton!
    private let minPriceField = NSTextField.numberInput(placeholder: "Min $", fractionDigits: 2)
    private let maxPriceField = NSTextField.numberInput(placeholder: "Max $", fractionDigits: 2)
    private let countLabel = NSTextField.label(font: Theme.font(12), color: Theme.textSecondary)
    private var table: DataTableView!
    private var results: [(Instrument, Quote)] = []
    private var sortKey = "cap"
    private var ascending = false

    init(env: AppEnvironment) {
        super.init(env: env, title: "Screener")
    }

    override func buildContent() {
        sectorPicker = .make(items: ["All Sectors"] + InstrumentCatalog.sectors, target: self, action: #selector(criteriaChanged))
        kindPicker = .make(items: ["Stocks & ETFs", "Stocks", "ETFs"], target: self, action: #selector(criteriaChanged))
        capPicker = .make(items: Self.marketCapOptions.map(\.0), target: self, action: #selector(criteriaChanged))
        changePicker = .make(items: Self.changeOptions.map(\.0), target: self, action: #selector(criteriaChanged))
        for field in [minPriceField, maxPriceField] {
            field.target = self
            field.action = #selector(criteriaChanged)
            field.widthAnchor.constraint(equalToConstant: 68).isActive = true
        }

        let filters = NSStackView(views: [sectorPicker, kindPicker, capPicker, changePicker, minPriceField, maxPriceField, countLabel])
        filters.spacing = 10
        filters.setVisibilityPriority(.detachOnlyIfNecessary, for: countLabel)
        for picker in [sectorPicker!, kindPicker!, capPicker!, changePicker!] {
            picker.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let filterBar = FillView(color: Theme.panelHeader)
        filterBar.borderEdges = [.bottom]
        filterBar.addSubviews(filters)

        table = DataTableView(columns: [
            TableColumnSpec(id: "symbol", title: "Symbol", width: 200, alignment: .left, sortable: true),
            TableColumnSpec(id: "sector", title: "Sector", width: 140, alignment: .left, sortable: true),
            TableColumnSpec(id: "last", title: "Price", width: 90, sortable: true),
            TableColumnSpec(id: "percent", title: "% Change", width: 90, sortable: true),
            TableColumnSpec(id: "volume", title: "Volume", width: 90, sortable: true),
            TableColumnSpec(id: "cap", title: "Market Cap", width: 100, sortable: true),
            TableColumnSpec(id: "pe", title: "P/E", width: 70, sortable: true),
            TableColumnSpec(id: "vol", title: "Volatility", width: 80, sortable: true),
        ], rowHeight: 36)
        table.rowCount = { [unowned self] in results.count }
        table.content = { [unowned self] row, column in cell(row: row, column: column) }
        table.onSelect = { [unowned self] row in env.link.select(results[row].0.symbol) }
        table.onSort = { [unowned self] key, isAscending in
            sortKey = key
            ascending = isAscending
            refresh()
        }

        view.addSubviews(filterBar, table)
        NSLayoutConstraint.activate([
            filterBar.topAnchor.constraint(equalTo: view.topAnchor),
            filterBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filterBar.heightAnchor.constraint(equalToConstant: 44),
            filters.leadingAnchor.constraint(equalTo: filterBar.leadingAnchor, constant: 12),
            filters.centerYAnchor.constraint(equalTo: filterBar.centerYAnchor),
            filters.trailingAnchor.constraint(lessThanOrEqualTo: filterBar.trailingAnchor, constant: -12),
            table.topAnchor.constraint(equalTo: filterBar.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func refresh() {
        let criteria = currentCriteria
        let isDownFilter = changePicker.indexOfSelectedItem == Self.changeOptions.count - 1
        let previous = results.map(\.0.symbol)
        results = env.market.instruments
            .filter(\.isTradable)
            .compactMap { instrument in env.market.quote(for: instrument.symbol).map { (instrument, $0) } }
            .filter { criteria.matches($0.0, $0.1) && (!isDownFilter || $0.1.changePercent < -0.01) }
            .sorted { ascending ? sortValue($0) < sortValue($1) : sortValue($0) > sortValue($1) }
        countLabel.stringValue = "\(results.count) results"
        if previous == results.map(\.0.symbol) {
            table.refresh()
        } else {
            table.tableView.reloadData()
        }
    }

    private var currentCriteria: Criteria {
        let kind: Instrument.Kind? = switch kindPicker.indexOfSelectedItem {
        case 1: .stock
        case 2: .etf
        default: nil
        }
        return Criteria(
            sector: sectorPicker.indexOfSelectedItem > 0 ? sectorPicker.titleOfSelectedItem : nil,
            kind: kind,
            minimumPrice: minPriceField.stringValue.isEmpty ? nil : minPriceField.doubleValue,
            maximumPrice: maxPriceField.stringValue.isEmpty ? nil : maxPriceField.doubleValue,
            minimumChange: Self.changeOptions[max(changePicker.indexOfSelectedItem, 0)].1,
            minimumMarketCap: Self.marketCapOptions[max(capPicker.indexOfSelectedItem, 0)].1
        )
    }

    private func sortValue(_ entry: (Instrument, Quote)) -> SortValue {
        let (instrument, quote) = entry
        switch sortKey {
        case "symbol": return .text(instrument.symbol)
        case "sector": return .text(instrument.sector)
        case "last": return .number(quote.last)
        case "percent": return .number(quote.changePercent)
        case "volume": return .number(quote.volume)
        case "pe": return .number(instrument.earningsPerShare > 0 ? quote.last / instrument.earningsPerShare : .greatestFiniteMagnitude)
        case "vol": return .number(instrument.volatility)
        default: return .number(instrument.sharesOutstanding * quote.last)
        }
    }

    private func cell(row: Int, column: String) -> CellContent {
        let (instrument, quote) = results[row]
        let trend = Theme.trendColor(quote.change)
        switch column {
        case "symbol": return .primary(instrument.symbol, secondary: instrument.name)
        case "sector": return .text(instrument.sector)
        case "last": return .number(Format.price(quote.last), color: trend)
        case "percent": return .number(Format.percent(quote.changePercent), color: trend)
        case "volume": return .number(Format.compact(quote.volume), color: Theme.textSecondary)
        case "cap": return .number(Format.compact(instrument.sharesOutstanding * quote.last))
        case "pe": return .number(instrument.earningsPerShare > 0 ? String(format: "%.1f", quote.last / instrument.earningsPerShare) : "--", color: Theme.textSecondary)
        case "vol": return .number(String(format: "%.0f%%", instrument.volatility * 100), color: Theme.textSecondary)
        default: return .text("")
        }
    }

    @objc private func criteriaChanged() {
        refresh()
    }
}

private enum SortValue: Comparable {
    case number(Double)
    case text(String)

    static func < (lhs: SortValue, rhs: SortValue) -> Bool {
        switch (lhs, rhs) {
        case let (.number(a), .number(b)): a < b
        case let (.text(a), .text(b)): a.localizedStandardCompare(b) == .orderedAscending
        default: false
        }
    }
}
