import AppKit

/// The left watchlist column: header tab, list picker, sortable column header and two-line rows.
final class WatchlistSidebar: PanelViewController, NSTableViewDataSource, NSTableViewDelegate {
    static let width: CGFloat = 189

    private enum SortOrder {
        case manual, descending, ascending
    }

    private static let listKey = "sidebar.watchlist"

    private let strip = TabStripView()
    private let picker = DropdownButton()
    private let sortButton = NSButton()
    private let tableView = NSTableView()
    private var listName = UserDefaults.standard.string(forKey: listKey) ?? WatchlistStore.recentlyViewedName
    private var symbols: [String] = []
    private var sortOrder = SortOrder.manual
    private var isSyncingSelection = false

    init(env: AppEnvironment) {
        super.init(env: env, title: "Watchlists")
    }

    override func buildContent() {
        strip.titles = ["Watchlists"]
        strip.trailingMenu = { [unowned self] in actionsMenu() }
        picker.onClick = { [unowned self] in showListMenu() }

        let columnHeader = FillView(color: Theme.panelBackground)
        let symbolIcon = NSImageView(image: NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)!)
        symbolIcon.contentTintColor = Theme.columnHeaderText
        symbolIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        let symbolTitle = NSTextField.label("Symbol", font: Theme.font(12.5), color: Theme.columnHeaderText)
        sortButton.isBordered = false
        sortButton.target = self
        sortButton.action = #selector(cycleSort)
        sortButton.imagePosition = .imageTrailing
        sortButton.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort")
        sortButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        sortButton.contentTintColor = Theme.columnHeaderText
        sortButton.toolTip = "Sort by % change"
        columnHeader.addSubviews(symbolIcon, symbolTitle, sortButton)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.intercellSpacing = .zero
        tableView.style = .plain
        tableView.backgroundColor = Theme.panelBackground
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.menu = NSMenu()
        tableView.menu?.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.panelBackground

        view.addSubviews(strip, picker, columnHeader, scroll)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: view.topAnchor),
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: TabStripView.height),
            picker.topAnchor.constraint(equalTo: strip.bottomAnchor, constant: 15),
            picker.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            picker.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            picker.heightAnchor.constraint(equalToConstant: 24),
            columnHeader.topAnchor.constraint(equalTo: picker.bottomAnchor, constant: 8),
            columnHeader.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            columnHeader.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            columnHeader.heightAnchor.constraint(equalToConstant: 26),
            symbolIcon.leadingAnchor.constraint(equalTo: columnHeader.leadingAnchor, constant: 10),
            symbolIcon.centerYAnchor.constraint(equalTo: columnHeader.centerYAnchor),
            symbolTitle.leadingAnchor.constraint(equalTo: symbolIcon.trailingAnchor, constant: 8),
            symbolTitle.centerYAnchor.constraint(equalTo: columnHeader.centerYAnchor),
            sortButton.trailingAnchor.constraint(equalTo: columnHeader.trailingAnchor, constant: -8),
            sortButton.centerYAnchor.constraint(equalTo: columnHeader.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: columnHeader.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        updateSortTitle()
        env.watchlists.changed.observe(self) { [weak self] in self?.reloadSymbols() }
        env.broker.changed.observe(self) { [weak self] in
            guard let self, self.isOnScreen else { return }
            self.redrawVisibleRows()
        }
        reloadSymbols()
    }

    override func refresh() {
        if sortOrder != .manual {
            let previous = symbols
            applySort()
            if previous != symbols {
                tableView.reloadData()
                syncSelection()
                return
            }
        }
        redrawVisibleRows()
    }

    override func linkedSymbolDidChange(_ symbol: String) {
        syncSelection()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        symbols.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: WatchRowView.identifier, owner: self) as? WatchRowView ?? WatchRowView()
        configure(cell, row: row)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSyncingSelection, tableView.selectedRow >= 0 else { return }
        env.link.select(symbols[tableView.selectedRow])
    }

    private func configure(_ cell: WatchRowView, row: Int) {
        let symbol = symbols[row]
        cell.symbol = symbol
        cell.name = env.market.instrument(symbol)?.name ?? ""
        cell.quote = env.market.quote(for: symbol)
        cell.hasPosition = env.broker.position(for: symbol) != nil
        cell.needsDisplay = true
    }

    private func redrawVisibleRows() {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        for row in visible.location..<(visible.location + visible.length) {
            if let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? WatchRowView {
                configure(cell, row: row)
            }
        }
    }

    private func syncSelection() {
        isSyncingSelection = true
        defer { isSyncingSelection = false }
        if let row = symbols.firstIndex(of: linkedSymbol) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
    }

    // MARK: Lists and sorting

    private func reloadSymbols() {
        if !env.watchlists.names.contains(listName) {
            listName = env.watchlists.names.first ?? listName
        }
        picker.title = listName
        symbols = env.watchlists.symbols(in: listName)
        applySort()
        tableView.reloadData()
        syncSelection()
    }

    private func applySort() {
        let base = env.watchlists.symbols(in: listName)
        guard sortOrder != .manual else {
            symbols = base
            return
        }
        let change: (String) -> Double = { [env] in env.market.quote(for: $0)?.changePercent ?? 0 }
        symbols = base.sorted { sortOrder == .descending ? change($0) > change($1) : change($0) < change($1) }
    }

    @objc private func cycleSort() {
        sortOrder = switch sortOrder {
        case .manual: .descending
        case .descending: .ascending
        case .ascending: .manual
        }
        updateSortTitle()
        reloadSymbols()
    }

    private func updateSortTitle() {
        let color = sortOrder == .manual ? Theme.columnHeaderText : Theme.accent
        sortButton.attributedTitle = NSAttributedString(string: "Price/Change ", attributes: [.font: Theme.font(12.5), .foregroundColor: Theme.columnHeaderText])
        sortButton.contentTintColor = color
    }

    private func showListMenu() {
        let menu = NSMenu()
        for name in env.watchlists.names {
            let item = NSMenuItem(title: name, action: #selector(selectList(_:)), keyEquivalent: "")
            item.target = self
            item.state = name == listName ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: picker.bounds.maxY + 4), in: picker)
    }

    private func actionsMenu() -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: "Add \(linkedSymbol) to \(listName)", action: #selector(addLinkedSymbol), keyEquivalent: "")
        add.target = self
        add.isEnabled = !symbols.contains(linkedSymbol)
        menu.addItem(add)
        if symbols.contains(linkedSymbol) {
            let remove = NSMenuItem(title: "Remove \(linkedSymbol) from \(listName)", action: #selector(removeLinkedSymbol), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
        }
        return menu
    }

    @objc private func selectList(_ sender: NSMenuItem) {
        listName = sender.title
        UserDefaults.standard.set(listName, forKey: Self.listKey)
        reloadSymbols()
    }

    @objc private func addLinkedSymbol() {
        env.watchlists.add(linkedSymbol, to: listName)
    }

    @objc private func removeLinkedSymbol() {
        env.watchlists.remove(linkedSymbol, from: listName)
    }

    @objc private func removeSymbol(_ sender: NSMenuItem) {
        guard let symbol = sender.representedObject as? String else { return }
        env.watchlists.remove(symbol, from: listName)
    }
}

extension WatchlistSidebar: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        let item = NSMenuItem(title: "Remove \(symbols[row]) from \(listName)", action: #selector(removeSymbol(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = symbols[row]
        menu.addItem(item)
    }
}

/// Rounded gray picker with a white disclosure triangle.
final class DropdownButton: NSView {
    var title = "" {
        didSet { needsDisplay = true }
    }

    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Theme.raisedBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: Theme.font(13), .foregroundColor: Theme.textPrimary]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: 14, y: (bounds.height - size.height) / 2), withAttributes: attributes)
        let triangle = NSBezierPath()
        let center = NSPoint(x: bounds.maxX - 18, y: bounds.midY + 2)
        triangle.move(to: NSPoint(x: center.x - 4.5, y: center.y - 3))
        triangle.line(to: NSPoint(x: center.x + 4.5, y: center.y - 3))
        triangle.line(to: NSPoint(x: center.x, y: center.y + 2))
        triangle.close()
        Theme.textPrimary.setFill()
        triangle.fill()
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }
}

private final class SidebarRowView: NSTableRowView {
    override func drawBackground(in dirtyRect: NSRect) {
        Theme.panelBackground.setFill()
        bounds.fill()
        Theme.rowSeparator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        Theme.selection.setFill()
        bounds.fill()
    }
}

/// Symbol and name on the left; price and change on the right, colored by direction.
private final class WatchRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("WatchRow")

    var symbol = ""
    var name = ""
    var quote: Quote?
    var hasPosition = false

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let inset: CGFloat = 10
        let topY: CGFloat = 10
        let bottomY: CGFloat = 29
        let symbolAttributes: [NSAttributedString.Key: Any] = [.font: Theme.font(13.5), .foregroundColor: Theme.textPrimary]
        (symbol as NSString).draw(at: NSPoint(x: inset, y: topY), withAttributes: symbolAttributes)
        let symbolWidth = (symbol as NSString).size(withAttributes: symbolAttributes).width
        if hasPosition {
            drawPositionBadge(at: NSPoint(x: inset + symbolWidth + 6, y: topY + 4))
        }

        guard let quote else { return }
        let color = Theme.trendColor(quote.change)
        let price = Format.legendPrice(quote.last) as NSString
        let priceAttributes: [NSAttributedString.Key: Any] = [.font: Theme.numberFont(13.5), .foregroundColor: color]
        let priceWidth = price.size(withAttributes: priceAttributes).width
        price.draw(at: NSPoint(x: bounds.width - inset - priceWidth, y: topY), withAttributes: priceAttributes)

        let change = "\(Format.signedLegendPrice(quote.change)) \(Format.percent(quote.changePercent))" as NSString
        let changeAttributes: [NSAttributedString.Key: Any] = [.font: Theme.numberFont(12), .foregroundColor: color]
        let changeWidth = change.size(withAttributes: changeAttributes).width
        change.draw(at: NSPoint(x: bounds.width - inset - changeWidth, y: bottomY), withAttributes: changeAttributes)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let nameRect = NSRect(x: inset, y: bottomY, width: max(0, bounds.width - inset * 2 - changeWidth - 6), height: 16)
        (name as NSString).draw(in: nameRect, withAttributes: [.font: Theme.font(12), .foregroundColor: Theme.textPrimary, .paragraphStyle: paragraph])
    }

    /// A small orange square marking symbols held in the paper account.
    private func drawPositionBadge(at origin: NSPoint) {
        let rect = NSRect(x: origin.x, y: origin.y, width: 11, height: 11)
        Theme.badge.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        NSColor.black.withAlphaComponent(0.75).setFill()
        for row in 0..<3 {
            NSRect(x: rect.minX + 2.5, y: rect.minY + 2.5 + CGFloat(row) * 2.5, width: 6, height: 1).fill()
        }
    }
}
