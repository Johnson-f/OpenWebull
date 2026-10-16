import AppKit

final class TimeAndSalesPanel: PanelViewController {
    private var table: DataTableView!
    private let summary = NSTextField.label(font: Theme.numberFont(11), color: Theme.textSecondary)
    private var prints: [TapePrint] = []

    init(env: AppEnvironment) {
        super.init(env: env, title: "Time & Sales")
    }

    override func buildContent() {
        table = DataTableView(columns: [
            TableColumnSpec(id: "time", title: "Time", width: 64, minWidth: 62, alignment: .left),
            TableColumnSpec(id: "price", title: "Price", width: 60, minWidth: 56),
            TableColumnSpec(id: "size", title: "Size", width: 52, minWidth: 46),
        ], rowHeight: 19)
        table.rowCount = { [unowned self] in prints.count }
        table.content = { [unowned self] row, column in cell(row: row, column: column) }

        view.addSubviews(summary, table)
        NSLayoutConstraint.activate([
            summary.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            summary.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8),
            table.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 6),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func refresh() {
        prints = env.market.recentTape(for: linkedSymbol)
        let buyVolume = prints.filter { $0.aggressor == .buyer }.reduce(0) { $0 + $1.size }
        let sellVolume = prints.filter { $0.aggressor == .seller }.reduce(0) { $0 + $1.size }
        summary.stringValue = "Buy \(Format.compact(Double(buyVolume)))  ·  Sell \(Format.compact(Double(sellVolume)))  ·  \(prints.count) prints"
        table.tableView.reloadData()
    }

    private func cell(row: Int, column: String) -> CellContent {
        let print = prints[row]
        let color: NSColor = switch print.aggressor {
        case .buyer: Theme.up
        case .seller: Theme.down
        case .neutral: Theme.textPrimary
        }
        let isBlock = print.size >= 1_000
        switch column {
        case "time": return CellContent(text: Format.clock(print.time), color: Theme.textSecondary, font: Theme.numberFont(11))
        case "price": return CellContent(text: Format.price(print.price), color: color, font: Theme.numberFont(11.5, isBlock ? .bold : .regular))
        default: return CellContent(text: Format.integer(print.size), color: color, font: Theme.numberFont(11.5, isBlock ? .bold : .regular))
        }
    }
}
