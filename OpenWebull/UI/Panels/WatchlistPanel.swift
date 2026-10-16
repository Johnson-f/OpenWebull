import AppKit

/// A watchlist in either a compact two-line style (sidebar) or a detailed multi-column style.
final class WatchlistPanel: PanelViewController {
    enum Density {
        case compact, detailed
    }

    private let density: Density
    private var listName = "My Watchlist"
    private var symbols: [String] = []
    private var listPicker: NSPopUpButton!
    private var table: DataTableView!

    init(env: AppEnvironment, density: Density) {
        self.density = density
        super.init(env: env, title: "Watchlists")
    }

    override func buildContent() {
        listPicker = .make(items: env.watchlists.names, target: self, action: #selector(listChanged))
        let addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Symbol")!, target: self, action: #selector(addLinkedSymbol))
        addButton.isBordered = false
        addButton.contentTintColor = Theme.textSecondary
        addButton.toolTip = "Add the linked symbol to this list"

        table = DataTableView(columns: columns, rowHeight: density == .compact ? 40 : 26)
        table.rowCount = { [unowned self] in symbols.count }
        table.content = { [unowned self] row, column in cell(row: row, column: column) }
        table.onSelect = { [unowned self] row in env.link.select(symbols[row]) }
        table.menuProvider = { [unowned self] row in contextMenu(for: row) }

        let header = FillView(color: Theme.panelBackground)
        header.addSubviews(listPicker, addButton)
        view.addSubviews(header, table)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),
            listPicker.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 8),
            listPicker.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            listPicker.trailingAnchor.constraint(lessThanOrEqualTo: addButton.leadingAnchor, constant: -8),
            addButton.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -10),
            addButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            table.topAnchor.constraint(equalTo: header.bottomAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        env.watchlists.changed.observe(self) { [weak self] in self?.reloadSymbols() }
        reloadSymbols()
    }

    override func refresh() {
        table.refresh()
    }

    override func linkedSymbolDidChange(_ symbol: String) {
        table.selectRow(symbols.firstIndex(of: symbol))
    }

    private var columns: [TableColumnSpec] {
        switch density {
        case .compact:
            [
                TableColumnSpec(id: "symbol", title: "Symbol", width: 110, minWidth: 80, alignment: .left),
                TableColumnSpec(id: "price", title: "Price", width: 80, minWidth: 64),
            ]
        case .detailed:
            [
                TableColumnSpec(id: "symbol", title: "Symbol", width: 80, alignment: .left),
                TableColumnSpec(id: "name", title: "Name", width: 150, alignment: .left),
                TableColumnSpec(id: "last", title: "Last", width: 80),
                TableColumnSpec(id: "change", title: "Change", width: 70),
                TableColumnSpec(id: "percent", title: "% Change", width: 76),
                TableColumnSpec(id: "bid", title: "Bid", width: 70),
                TableColumnSpec(id: "ask", title: "Ask", width: 70),
                TableColumnSpec(id: "volume", title: "Volume", width: 80),
                TableColumnSpec(id: "cap", title: "Mkt Cap", width: 80),
                TableColumnSpec(id: "trend", title: "Day Range", width: 110),
            ]
        }
    }

    private func cell(row: Int, column: String) -> CellContent {
        let symbol = symbols[row]
        guard let quote = env.market.quote(for: symbol), let instrument = env.market.instrument(symbol) else {
            return .text("--")
        }
        let trend = Theme.trendColor(quote.change)
        switch column {
        case "symbol" where density == .compact:
            return .primary(symbol, secondary: instrument.name)
        case "price":
            return CellContent(text: Format.price(quote.last), color: trend, font: Theme.numberFont(12, .medium), secondaryText: Format.percent(quote.changePercent), secondaryColor: trend)
        case "symbol":
            return .primary(symbol)
        case "name":
            return .text(instrument.name)
        case "last":
            return .number(Format.price(quote.last), color: trend)
        case "change":
            return .number(Format.signedPrice(quote.change), color: trend)
        case "percent":
            return .number(Format.percent(quote.changePercent), color: trend)
        case "bid":
            return .number(instrument.isTradable ? Format.price(quote.bid) : "--")
        case "ask":
            return .number(instrument.isTradable ? Format.price(quote.ask) : "--")
        case "volume":
            return .number(instrument.isTradable ? Format.compact(quote.volume) : "--", color: Theme.textSecondary)
        case "cap":
            return .number(instrument.kind == .stock ? Format.compact(instrument.sharesOutstanding * quote.last) : "--", color: Theme.textSecondary)
        case "trend":
            return .number("\(Format.price(quote.low)) – \(Format.price(quote.high))", color: Theme.textSecondary)
        default:
            return .text("")
        }
    }

    private func contextMenu(for row: Int) -> NSMenu {
        let menu = NSMenu()
        let remove = NSMenuItem(title: "Remove \(symbols[row]) from \(listName)", action: #selector(removeSymbol(_:)), keyEquivalent: "")
        remove.target = self
        remove.representedObject = symbols[row]
        menu.addItem(remove)
        return menu
    }

    private func reloadSymbols() {
        let names = env.watchlists.names
        if listPicker.itemTitles != names {
            listPicker.removeAllItems()
            listPicker.addItems(withTitles: names)
        }
        listPicker.selectItem(withTitle: listName)
        symbols = env.watchlists.symbols(in: listName)
        table.tableView.reloadData()
        table.selectRow(symbols.firstIndex(of: linkedSymbol))
    }

    @objc private func listChanged() {
        listName = listPicker.titleOfSelectedItem ?? listName
        reloadSymbols()
    }

    @objc private func addLinkedSymbol() {
        env.watchlists.add(linkedSymbol, to: listName)
    }

    @objc private func removeSymbol(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else { return }
        env.watchlists.remove(symbol, from: listName)
    }
}
