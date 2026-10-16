import AppKit

final class NewsPanel: PanelViewController {
    private var scope: NSSegmentedControl!
    private var table: DataTableView!
    private var items: [NewsItem] = []
    private var lastLoadedCount = -1

    init(env: AppEnvironment) {
        super.init(env: env, title: "News")
    }

    override func buildContent() {
        scope = .make(labels: ["Linked Symbol", "All Market"], target: self, action: #selector(scopeChanged))
        table = DataTableView(columns: [
            TableColumnSpec(id: "headline", title: "Headline", width: 420, alignment: .left),
            TableColumnSpec(id: "time", title: "Time", width: 90, minWidth: 80),
        ], rowHeight: 40)
        table.rowCount = { [unowned self] in items.count }
        table.content = { [unowned self] row, column in
            let item = items[row]
            if column == "time" {
                return .text(Format.dateTime(item.time))
            }
            return CellContent(text: item.headline, font: Theme.font(12.5), secondaryText: "\(item.symbol) · \(item.source)")
        }
        table.onDoubleClick = { [unowned self] row in env.link.select(items[row].symbol) }

        view.addSubviews(scope, table)
        NSLayoutConstraint.activate([
            scope.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            scope.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            table.topAnchor.constraint(equalTo: scope.bottomAnchor, constant: 6),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func refresh() {
        let symbol = scope.selectedSegment == 0 ? linkedSymbol : nil
        let latest = env.market.news(for: symbol)
        guard latest.count != lastLoadedCount || latest.first?.time != items.first?.time else { return }
        items = latest
        lastLoadedCount = latest.count
        table.tableView.reloadData()
    }

    override func linkedSymbolDidChange(_ symbol: String) {
        lastLoadedCount = -1
        refresh()
    }

    @objc private func scopeChanged() {
        lastLoadedCount = -1
        refresh()
    }
}
