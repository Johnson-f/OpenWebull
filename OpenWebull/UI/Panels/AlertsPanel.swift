import AppKit

final class AlertsPanel: PanelViewController {
    private var table: DataTableView!
    private var alerts: [AlertStore.PriceAlert] = []
    private let hint = NSTextField.label("Create alerts from the bell in the chart legend. Right-click an alert to delete it.", font: Theme.font(12.5), color: Theme.textTertiary)

    init(env: AppEnvironment) {
        super.init(env: env, title: "My Alerts")
    }

    override func buildContent() {
        table = DataTableView(columns: [
            TableColumnSpec(id: "symbol", title: "Symbol", width: 120, alignment: .left),
            TableColumnSpec(id: "condition", title: "Condition", width: 200, alignment: .left),
            TableColumnSpec(id: "last", title: "Last", width: 100),
            TableColumnSpec(id: "created", title: "Created", width: 140),
            TableColumnSpec(id: "status", title: "Status", width: 160, alignment: .left),
        ], rowHeight: 30)
        table.rowCount = { [unowned self] in alerts.count }
        table.content = { [unowned self] row, column in cell(alerts[row], column: column) }
        table.onSelect = { [unowned self] row in env.link.select(alerts[row].symbol) }
        table.menuProvider = { [unowned self] row in
            let menu = NSMenu()
            let delete = NSMenuItem(title: "Delete Alert", action: #selector(deleteAlert(_:)), keyEquivalent: "")
            delete.target = self
            delete.representedObject = alerts[row].id
            menu.addItem(delete)
            return menu
        }
        view.addSubviews(hint, table)
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            table.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 8),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        env.alerts.changed.observe(self) { [weak self] in self?.reload() }
    }

    override func refresh() {
        if alerts.count != env.alerts.alerts.count { reload() } else { table.refresh() }
    }

    private func reload() {
        guard isViewLoaded else { return }
        alerts = env.alerts.alerts
        table.tableView.reloadData()
    }

    private func cell(_ alert: AlertStore.PriceAlert, column: String) -> CellContent {
        switch column {
        case "symbol": return .primary(alert.symbol)
        case "condition": return .text("Price \(alert.triggersAbove ? "rises to" : "falls to") \(Format.legendPrice(alert.price))", color: Theme.textPrimary)
        case "last": return .number(env.market.quote(for: alert.symbol).map { Format.legendPrice($0.last) } ?? "--")
        case "created": return .number(Format.dateTime(alert.createdAt), color: Theme.textSecondary)
        default:
            if let fired = alert.triggeredAt {
                return CellContent(text: "Triggered \(Format.clock(fired))", color: Theme.up, font: Theme.font(13, .medium))
            }
            return CellContent(text: "Active", color: Theme.accent, font: Theme.font(13, .medium))
        }
    }

    @objc private func deleteAlert(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        env.alerts.remove(id)
    }
}
