import AppKit

final class OrdersPanel: PanelViewController {
    private enum Filter: String, CaseIterable {
        case working = "Working"
        case filled = "Filled"
        case cancelled = "Cancelled"
        case all = "All"

        func includes(_ order: Order) -> Bool {
            switch self {
            case .working: order.status.isOpen
            case .filled: order.status == .filled
            case .cancelled: order.status == .cancelled || order.status == .rejected
            case .all: true
            }
        }
    }

    private var filterControl: NSSegmentedControl!
    private var table: DataTableView!
    private var orders: [Order] = []

    init(env: AppEnvironment) {
        super.init(env: env, title: "Orders")
    }

    override func buildContent() {
        filterControl = .make(labels: Filter.allCases.map(\.rawValue), target: self, action: #selector(filterChanged))
        filterControl.selectedSegment = Filter.allCases.firstIndex(of: .all)!
        let cancelAll = NSButton(title: "Cancel All", target: self, action: #selector(cancelAll))
        cancelAll.controlSize = .small
        cancelAll.bezelStyle = .rounded
        cancelAll.translatesAutoresizingMaskIntoConstraints = false

        table = DataTableView(columns: [
            TableColumnSpec(id: "time", title: "Placed", width: 90, alignment: .left),
            TableColumnSpec(id: "symbol", title: "Symbol", width: 70, alignment: .left),
            TableColumnSpec(id: "side", title: "Side", width: 50, alignment: .left),
            TableColumnSpec(id: "type", title: "Type", width: 76, alignment: .left),
            TableColumnSpec(id: "quantity", title: "Qty", width: 54),
            TableColumnSpec(id: "filled", title: "Filled", width: 54),
            TableColumnSpec(id: "price", title: "Limit / Stop", width: 100),
            TableColumnSpec(id: "average", title: "Avg Fill", width: 76),
            TableColumnSpec(id: "tif", title: "TIF", width: 48, alignment: .center),
            TableColumnSpec(id: "status", title: "Status", width: 80, alignment: .left),
        ])
        table.rowCount = { [unowned self] in orders.count }
        table.content = { [unowned self] row, column in cell(row: row, column: column) }
        table.onSelect = { [unowned self] row in env.link.select(orders[row].symbol) }
        table.menuProvider = { [unowned self] row in contextMenu(for: orders[row]) }

        view.addSubviews(filterControl, cancelAll, table)
        NSLayoutConstraint.activate([
            filterControl.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            filterControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            cancelAll.centerYAnchor.constraint(equalTo: filterControl.centerYAnchor),
            cancelAll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            table.topAnchor.constraint(equalTo: filterControl.bottomAnchor, constant: 6),
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
        let filter = Filter.allCases[filterControl.selectedSegment]
        let previous = orders.map { "\($0.id)\($0.status)" }
        orders = env.broker.orders.filter(filter.includes)
        if previous != orders.map({ "\($0.id)\($0.status)" }) {
            table.tableView.reloadData()
        }
    }

    private func cell(row: Int, column: String) -> CellContent {
        let order = orders[row]
        let ticket = order.ticket
        switch column {
        case "time": return .text(Format.dateTime(order.createdAt))
        case "symbol": return .primary(ticket.symbol)
        case "side": return CellContent(text: ticket.side.rawValue, color: Theme.trendColor(ticket.side.sign), font: Theme.font(12, .medium))
        case "type": return .text(ticket.type.rawValue)
        case "quantity": return .number(Format.integer(ticket.quantity))
        case "filled": return .number(Format.integer(order.filledQuantity), color: Theme.textSecondary)
        case "price":
            let prices = [ticket.limitPrice.map(Format.price), ticket.stopPrice.map { "stop \(Format.price($0))" }].compactMap { $0 }
            return .number(prices.isEmpty ? "MKT" : prices.joined(separator: " / "))
        case "average": return .number(order.averageFillPrice.map(Format.price) ?? "--")
        case "tif": return .text(ticket.timeInForce.rawValue)
        case "status":
            let color: NSColor = switch order.status {
            case .working: order.stopTriggered ? Theme.warning : Theme.accent
            case .filled: Theme.up
            case .cancelled, .rejected: Theme.textTertiary
            }
            return CellContent(text: order.stopTriggered && order.status.isOpen ? "Triggered" : order.status.rawValue, color: color, font: Theme.font(12, .medium))
        default: return .text("")
        }
    }

    private func contextMenu(for order: Order) -> NSMenu? {
        guard order.status.isOpen else { return nil }
        let menu = NSMenu()
        let cancel = NSMenuItem(title: "Cancel Order", action: #selector(cancelOrder(_:)), keyEquivalent: "")
        cancel.target = self
        cancel.representedObject = order.id
        menu.addItem(cancel)
        return menu
    }

    @objc private func cancelOrder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        env.broker.cancel(id)
    }

    @objc private func cancelAll() {
        env.broker.cancelAllWorkingOrders()
    }

    @objc private func filterChanged() {
        orders = []
        refresh()
    }
}
