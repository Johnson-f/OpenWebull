import AppKit

/// Base for research tabs whose rows are regenerated only when the linked symbol changes.
class SymbolTablePanel<Row>: PanelViewController {
    private(set) var rows: [Row] = []
    private(set) var table: DataTableView!
    private let caption = NSTextField.label(font: Theme.font(12), color: Theme.textTertiary)

    var columns: [TableColumnSpec] { [] }
    var rowHeight: CGFloat { 30 }
    var footnote: String { "Simulated data for demonstration." }

    func makeRows(for instrument: Instrument) -> [Row] { [] }
    func cell(_ row: Row, column: String) -> CellContent { .text("") }

    override func buildContent() {
        table = DataTableView(columns: columns, rowHeight: rowHeight)
        table.rowCount = { [unowned self] in rows.count }
        table.content = { [unowned self] row, column in cell(rows[row], column: column) }
        caption.stringValue = footnote
        view.addSubviews(table, caption)
        NSLayoutConstraint.activate([
            table.topAnchor.constraint(equalTo: view.topAnchor),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -6),
            caption.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            caption.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
        ])
    }

    override func marketDidTick() {}

    override func refresh() {
        guard let instrument = env.market.instrument(linkedSymbol) else { return }
        rows = makeRows(for: instrument)
        table.tableView.reloadData()
    }
}

final class CorporateActionsPanel: SymbolTablePanel<ResearchGenerator.CorporateAction> {
    init(env: AppEnvironment) { super.init(env: env, title: "Corp Actions") }

    override var columns: [TableColumnSpec] {
        [
            TableColumnSpec(id: "date", title: "Date", width: 110, alignment: .left),
            TableColumnSpec(id: "kind", title: "Event", width: 160, alignment: .left),
            TableColumnSpec(id: "detail", title: "Details", width: 420, alignment: .left),
        ]
    }

    override func makeRows(for instrument: Instrument) -> [ResearchGenerator.CorporateAction] {
        ResearchGenerator.corporateActions(for: instrument, now: Date())
    }

    override func cell(_ row: ResearchGenerator.CorporateAction, column: String) -> CellContent {
        switch column {
        case "date": .number(Format.mediumDate(row.date), color: Theme.textSecondary)
        case "kind": CellContent(text: row.kind, color: row.date > Date() ? Theme.accent : Theme.textPrimary, font: Theme.font(13))
        default: .text(row.detail)
        }
    }
}

final class InstitutionsPanel: SymbolTablePanel<ResearchGenerator.Holder> {
    init(env: AppEnvironment) { super.init(env: env, title: "Institutions") }

    override var columns: [TableColumnSpec] {
        [
            TableColumnSpec(id: "name", title: "Institution", width: 240, alignment: .left),
            TableColumnSpec(id: "shares", title: "Shares Held", width: 110),
            TableColumnSpec(id: "percent", title: "% Outstanding", width: 110),
            TableColumnSpec(id: "change", title: "Change", width: 110),
            TableColumnSpec(id: "date", title: "Reported", width: 110),
        ]
    }

    override var footnote: String { "Institution names and holdings are fictional." }

    override func makeRows(for instrument: Instrument) -> [ResearchGenerator.Holder] {
        ResearchGenerator.institutions(for: instrument, now: Date())
    }

    override func cell(_ row: ResearchGenerator.Holder, column: String) -> CellContent {
        switch column {
        case "name": CellContent(text: row.name, font: Theme.font(13))
        case "shares": .number(Format.compact(row.shares))
        case "percent": .number(String(format: "%.2f%%", row.percentOutstanding * 100))
        case "change": .number((row.changeShares > 0 ? "+" : "") + Format.compact(row.changeShares), color: Theme.trendColor(row.changeShares))
        default: .number(Format.mediumDate(row.reportedAt), color: Theme.textSecondary)
        }
    }
}

final class MessagesPanel: SymbolTablePanel<ResearchGenerator.Post> {
    init(env: AppEnvironment) { super.init(env: env, title: "Messages") }

    override var rowHeight: CGFloat { 46 }
    override var footnote: String { "Simulated community posts. Not investment advice." }

    override var columns: [TableColumnSpec] {
        [
            TableColumnSpec(id: "post", title: "Post", width: 520, alignment: .left),
            TableColumnSpec(id: "sentiment", title: "Sentiment", width: 90, alignment: .left),
            TableColumnSpec(id: "likes", title: "Likes", width: 60),
        ]
    }

    override func makeRows(for instrument: Instrument) -> [ResearchGenerator.Post] {
        ResearchGenerator.posts(for: instrument, now: Date())
    }

    override func cell(_ row: ResearchGenerator.Post, column: String) -> CellContent {
        switch column {
        case "post": CellContent(text: row.text, font: Theme.font(13), secondaryText: "@\(row.author) · \(Format.dateTime(row.time))")
        case "sentiment": CellContent(text: row.isBullish ? "Bullish" : "Bearish", color: row.isBullish ? Theme.up : Theme.down, font: Theme.font(12.5, .medium))
        default: .number(Format.integer(row.likes), color: Theme.textSecondary)
        }
    }
}

final class FinancialsPanel: SymbolTablePanel<(metric: String, values: [String])> {
    private var periods: [String] = []

    init(env: AppEnvironment) { super.init(env: env, title: "Financials") }

    override var columns: [TableColumnSpec] {
        [TableColumnSpec(id: "metric", title: "Quarterly", width: 160, alignment: .left)]
            + (0..<8).map { TableColumnSpec(id: "q\($0)", title: "Q", width: 92) }
    }

    override func makeRows(for instrument: Instrument) -> [(metric: String, values: [String])] {
        let quarters = ResearchGenerator.financials(for: instrument, now: Date())
        periods = quarters.map(\.period)
        for (index, column) in table.tableView.tableColumns.dropFirst().enumerated() where index < periods.count {
            column.headerCell.stringValue = periods[index]
        }
        table.tableView.headerView?.needsDisplay = true
        guard instrument.kind == .stock else { return [] }
        return [
            ("Revenue", quarters.map { Format.compact($0.revenue) }),
            ("Gross Profit", quarters.map { Format.compact($0.grossProfit) }),
            ("Operating Income", quarters.map { Format.compact($0.operatingIncome) }),
            ("Net Income", quarters.map { Format.compact($0.netIncome) }),
            ("EPS", quarters.map { String(format: "%.2f", $0.eps) }),
            ("Net Margin", quarters.map { $0.revenue == 0 ? "--" : String(format: "%.1f%%", $0.netIncome / $0.revenue * 100) }),
        ]
    }

    override func cell(_ row: (metric: String, values: [String]), column: String) -> CellContent {
        if column == "metric" { return CellContent(text: row.metric, color: Theme.textSecondary, font: Theme.font(13)) }
        let index = Int(column.dropFirst()) ?? 0
        return .number(index < row.values.count ? row.values[index] : "--")
    }
}

final class ReleasesPanel: SymbolTablePanel<ResearchGenerator.EarningsRelease> {
    init(env: AppEnvironment) { super.init(env: env, title: "Releases") }

    override var columns: [TableColumnSpec] {
        [
            TableColumnSpec(id: "date", title: "Date", width: 110, alignment: .left),
            TableColumnSpec(id: "period", title: "Period", width: 110, alignment: .left),
            TableColumnSpec(id: "epsEst", title: "EPS Est.", width: 90),
            TableColumnSpec(id: "eps", title: "EPS Actual", width: 90),
            TableColumnSpec(id: "surprise", title: "Surprise", width: 90),
            TableColumnSpec(id: "revEst", title: "Revenue Est.", width: 110),
            TableColumnSpec(id: "rev", title: "Revenue", width: 110),
        ]
    }

    override func makeRows(for instrument: Instrument) -> [ResearchGenerator.EarningsRelease] {
        instrument.kind == .stock ? ResearchGenerator.releases(for: instrument, now: Date()) : []
    }

    override func cell(_ row: ResearchGenerator.EarningsRelease, column: String) -> CellContent {
        switch column {
        case "date": return .number(Format.mediumDate(row.date), color: Theme.textSecondary)
        case "period": return CellContent(text: row.period, color: row.epsActual == nil ? Theme.accent : Theme.textPrimary, font: Theme.font(13))
        case "epsEst": return .number(String(format: "%.2f", row.epsEstimate))
        case "eps": return .number(row.epsActual.map { String(format: "%.2f", $0) } ?? "--")
        case "surprise":
            guard let actual = row.epsActual, row.epsEstimate != 0 else { return .number("--") }
            let surprise = (actual - row.epsEstimate) / abs(row.epsEstimate)
            return .number(Format.percent(surprise), color: Theme.trendColor(surprise))
        case "revEst": return .number(Format.compact(row.revenueEstimate))
        default: return .number(row.revenueActual.map(Format.compact) ?? "--")
        }
    }
}

/// Quote header with depth and the tape side by side.
final class QuotesPanel: PanelViewController {
    private let header = QuoteHeaderView()

    init(env: AppEnvironment) { super.init(env: env, title: "Quotes") }

    override func buildContent() {
        let depth = Level2Panel(env: env)
        let tape = TimeAndSalesPanel(env: env)
        [depth, tape].forEach(addChild)
        let split = WeightedSplitView(vertical: true, views: [depth.view, tape.view], weights: [0.62, 0.38])
        view.addSubviews(header, split)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.topAnchor.constraint(equalTo: header.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func refresh() {
        guard let instrument = env.market.instrument(linkedSymbol), let quote = env.market.quote(for: linkedSymbol) else { return }
        header.update(instrument: instrument, quote: quote)
    }
}

/// The paper position and order history for the linked symbol.
final class SymbolPnLPanel: PanelViewController {
    private let summary = NSTextField.label(font: Theme.numberFont(14), color: Theme.textPrimary)
    private let detail = NSTextField.label(font: Theme.numberFont(12.5), color: Theme.textSecondary)
    private var table: DataTableView!
    private var orders: [Order] = []

    init(env: AppEnvironment) { super.init(env: env, title: "P&L") }

    override func buildContent() {
        table = DataTableView(columns: [
            TableColumnSpec(id: "time", title: "Placed", width: 110, alignment: .left),
            TableColumnSpec(id: "side", title: "Side", width: 60, alignment: .left),
            TableColumnSpec(id: "type", title: "Type", width: 90, alignment: .left),
            TableColumnSpec(id: "qty", title: "Qty", width: 70),
            TableColumnSpec(id: "price", title: "Avg Fill", width: 90),
            TableColumnSpec(id: "status", title: "Status", width: 90, alignment: .left),
        ])
        table.rowCount = { [unowned self] in orders.count }
        table.content = { [unowned self] row, column in
            let order = orders[row]
            switch column {
            case "time": return .number(Format.dateTime(order.createdAt), color: Theme.textSecondary)
            case "side": return CellContent(text: order.ticket.side.rawValue, color: Theme.trendColor(order.ticket.side.sign), font: Theme.font(13))
            case "type": return .text(order.ticket.type.rawValue)
            case "qty": return .number(Format.integer(order.ticket.quantity))
            case "price": return .number(order.averageFillPrice.map(Format.legendPrice) ?? "--")
            default: return .text(order.status.rawValue, color: order.status == .filled ? Theme.up : Theme.textSecondary)
            }
        }
        view.addSubviews(summary, detail, table)
        NSLayoutConstraint.activate([
            summary.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            summary.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            detail.topAnchor.constraint(equalTo: summary.bottomAnchor, constant: 6),
            detail.leadingAnchor.constraint(equalTo: summary.leadingAnchor),
            table.topAnchor.constraint(equalTo: detail.bottomAnchor, constant: 14),
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
        guard let quote = env.market.quote(for: linkedSymbol) else { return }
        let previousCount = orders.count
        orders = env.broker.orders.filter { $0.symbol == linkedSymbol }
        if let position = env.broker.position(for: linkedSymbol) {
            let pnl = position.unrealizedPnL(at: quote.last)
            summary.stringValue = "\(linkedSymbol)  \(position.quantity) shares @ \(Format.legendPrice(position.averageCost))"
            detail.stringValue = "Market value \(Format.currency(position.marketValue(at: quote.last)))   Unrealized \(Format.signedCurrency(pnl)) (\(Format.percent(position.unrealizedPnLPercent(at: quote.last))))"
            detail.textColor = Theme.trendColor(pnl)
        } else {
            summary.stringValue = "No position in \(linkedSymbol)"
            detail.stringValue = "Use the Trade panel on the right rail to place a paper order."
            detail.textColor = Theme.textSecondary
        }
        if previousCount != orders.count { table.tableView.reloadData() } else { table.refresh() }
    }
}

/// A free-form note per symbol, saved locally.
final class NotePanel: PanelViewController, NSTextViewDelegate {
    private let textView = NSTextView()
    private let caption = NSTextField.label(font: Theme.font(12), color: Theme.textTertiary)
    private var editingSymbol = ""

    init(env: AppEnvironment) { super.init(env: env, title: "Note") }

    override func buildContent() {
        textView.isRichText = false
        textView.font = Theme.font(14)
        textView.textColor = Theme.textPrimary
        textView.backgroundColor = Theme.panelBackground
        textView.insertionPointColor = Theme.accent
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        view.addSubviews(caption, scroll)
        NSLayoutConstraint.activate([
            caption.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            caption.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            scroll.topAnchor.constraint(equalTo: caption.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func marketDidTick() {}

    override func refresh() {
        guard editingSymbol != linkedSymbol else { return }
        editingSymbol = linkedSymbol
        caption.stringValue = "Notes for \(linkedSymbol) · saved on this Mac"
        textView.string = UserDefaults.standard.string(forKey: Self.key(for: linkedSymbol)) ?? ""
    }

    func textDidChange(_ notification: Notification) {
        UserDefaults.standard.set(textView.string, forKey: Self.key(for: editingSymbol))
    }

    private static func key(for symbol: String) -> String { "note.\(symbol)" }
}
