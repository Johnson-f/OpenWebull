import AppKit

final class PositionsPanel: PanelViewController {
    private var table: DataTableView!
    private let totals = NSTextField.label(font: Theme.numberFont(11.5), color: Theme.textSecondary)
    private var positions: [Position] = []

    init(env: AppEnvironment) {
        super.init(env: env, title: "Positions")
    }

    override func buildContent() {
        table = DataTableView(columns: [
            TableColumnSpec(id: "symbol", title: "Symbol", width: 120, alignment: .left),
            TableColumnSpec(id: "quantity", title: "Qty", width: 60),
            TableColumnSpec(id: "cost", title: "Avg Cost", width: 80),
            TableColumnSpec(id: "last", title: "Last", width: 80),
            TableColumnSpec(id: "value", title: "Mkt Value", width: 96),
            TableColumnSpec(id: "day", title: "Day P&L", width: 90),
            TableColumnSpec(id: "pnl", title: "Unrealized P&L", width: 110),
            TableColumnSpec(id: "percent", title: "P&L %", width: 70),
        ], rowHeight: 34)
        table.rowCount = { [unowned self] in positions.count }
        table.content = { [unowned self] row, column in cell(row: row, column: column) }
        table.onSelect = { [unowned self] row in env.link.select(positions[row].symbol) }
        table.menuProvider = { [unowned self] row in contextMenu(for: positions[row]) }

        view.addSubviews(totals, table)
        NSLayoutConstraint.activate([
            totals.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            totals.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            totals.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),
            table.topAnchor.constraint(equalTo: totals.bottomAnchor, constant: 6),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        env.broker.changed.observe(self) { [weak self] in
            guard let self, self.isOnScreen else { return }
            self.refresh()
        }
    }

    override func marketDidTick() {}

    override func refresh() {
        let symbols = positions.map(\.symbol)
        positions = env.broker.sortedPositions
        if symbols != positions.map(\.symbol) {
            table.tableView.reloadData()
        } else {
            table.refresh()
        }
        let snapshot = env.broker.snapshot()
        totals.stringValue = "\(positions.count) positions · Unrealized \(Format.signedCurrency(snapshot.unrealizedPnL)) · Realized \(Format.signedCurrency(snapshot.realizedPnL))"
    }

    private func cell(row: Int, column: String) -> CellContent {
        let position = positions[row]
        guard let quote = env.market.quote(for: position.symbol) else { return .text("--") }
        let pnl = position.unrealizedPnL(at: quote.last)
        let dayPnL = Double(position.quantity) * quote.change
        switch column {
        case "symbol": return .primary(position.symbol, secondary: position.isShort ? "Short" : env.market.instrument(position.symbol)?.name)
        case "quantity": return .number(Format.integer(position.quantity))
        case "cost": return .number(Format.price(position.averageCost))
        case "last": return .number(Format.price(quote.last), color: Theme.trendColor(quote.change))
        case "value": return .number(Format.currency(position.marketValue(at: quote.last)))
        case "day": return .number(Format.signedCurrency(dayPnL), color: Theme.trendColor(dayPnL))
        case "pnl": return .number(Format.signedCurrency(pnl), color: Theme.trendColor(pnl))
        case "percent": return .number(Format.percent(position.unrealizedPnLPercent(at: quote.last)), color: Theme.trendColor(pnl))
        default: return .text("")
        }
    }

    private func contextMenu(for position: Position) -> NSMenu {
        let menu = NSMenu()
        let close = NSMenuItem(title: "Close \(abs(position.quantity)) \(position.symbol) at Market", action: #selector(closePosition(_:)), keyEquivalent: "")
        close.target = self
        close.representedObject = position.symbol
        menu.addItem(close)
        return menu
    }

    @objc private func closePosition(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else { return }
        env.broker.closePosition(symbol)
    }
}
