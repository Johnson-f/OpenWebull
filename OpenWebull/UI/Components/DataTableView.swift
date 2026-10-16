import AppKit

struct TableColumnSpec {
    let id: String
    let title: String
    var width: CGFloat = 80
    var minWidth: CGFloat?
    var alignment: NSTextAlignment = .right
    var sortable = false
}

struct CellContent {
    var text: String
    var color: NSColor = Theme.textPrimary
    var font: NSFont = Theme.numberFont(12)
    var secondaryText: String?
    var secondaryColor: NSColor = Theme.textSecondary
    var background: NSColor?

    static func primary(_ text: String, secondary: String? = nil) -> CellContent {
        CellContent(text: text, font: Theme.font(12, .semibold), secondaryText: secondary)
    }

    static func number(_ text: String, color: NSColor = Theme.textPrimary) -> CellContent {
        CellContent(text: text, color: color)
    }

    static func text(_ text: String, color: NSColor = Theme.textSecondary) -> CellContent {
        CellContent(text: text, color: color, font: Theme.font(12))
    }
}

/// A closure-driven, view-based table styled for dense market data.
final class DataTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var rowCount: () -> Int = { 0 }
    var content: (_ row: Int, _ column: String) -> CellContent = { _, _ in CellContent(text: "") }
    var onSelect: ((Int) -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    var onSort: ((_ column: String, _ ascending: Bool) -> Void)?

    let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var columnAlignments: [String: NSTextAlignment] = [:]
    private var lastRowCount = 0
    private var isApplyingSelection = false
    private var lastFittedWidth: CGFloat = 0

    init(columns: [TableColumnSpec], rowHeight: CGFloat = 22, showsHeader: Bool = true) {
        super.init(frame: .zero)
        for spec in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(spec.id))
            column.headerCell = DarkHeaderCell(textCell: spec.title)
            column.headerCell.alignment = spec.alignment
            column.width = spec.width
            column.minWidth = spec.minWidth ?? spec.width * 0.85
            if spec.sortable {
                column.sortDescriptorPrototype = NSSortDescriptor(key: spec.id, ascending: false)
            }
            columnAlignments[spec.id] = spec.alignment
            tableView.addTableColumn(column)
        }
        tableView.style = .plain
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = Theme.panelBackground
        tableView.gridStyleMask = []
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.allowsColumnReordering = false
        tableView.usesAutomaticRowHeights = false
        tableView.headerView = showsHeader ? NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 26)) : nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.menu = NSMenu()
        tableView.menu?.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.panelBackground
        scrollView.borderType = .noBorder
        addSubview(scrollView)
        scrollView.pinEdges(to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Columns stretch or shrink to the panel width down to their minimum widths, then scroll horizontally.
    override func layout() {
        super.layout()
        let width = scrollView.contentView.bounds.width
        guard width > 0, abs(width - lastFittedWidth) > 0.5 else { return }
        lastFittedWidth = width
        tableView.sizeToFit()
    }

    var selectedRow: Int? {
        tableView.selectedRow >= 0 ? tableView.selectedRow : nil
    }

    /// Reloads only the visible rows when the row count is unchanged, keeping scroll and selection steady.
    func refresh() {
        let count = rowCount()
        guard count == lastRowCount, count > 0 else {
            lastRowCount = count
            tableView.reloadData()
            return
        }
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return }
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)),
            columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns)
        )
    }

    func selectRow(_ row: Int?) {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        guard let row, row < tableView.numberOfRows else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        rowCount()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? DataCellView ?? DataCellView(identifier: identifier)
        cell.apply(content(row, identifier.rawValue), alignment: columnAlignments[identifier.rawValue] ?? .left)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        DataRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingSelection, tableView.selectedRow >= 0 else { return }
        onSelect?(tableView.selectedRow)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first, let key = descriptor.key else { return }
        onSort?(key, descriptor.ascending)
    }

    @objc private func handleDoubleClick() {
        guard tableView.clickedRow >= 0 else { return }
        onDoubleClick?(tableView.clickedRow)
    }
}

extension DataTableView: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, let provided = menuProvider?(row) else { return }
        for item in provided.items {
            provided.removeItem(item)
            menu.addItem(item)
        }
    }
}

private final class DataRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        Theme.selection.setFill()
        bounds.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        Theme.panelBackground.setFill()
        bounds.fill()
        Theme.rowSeparator.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}

private final class DarkHeaderCell: NSTableHeaderCell {
    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        Theme.panelBackground.setFill()
        cellFrame.fill()
        Theme.separator.setFill()
        NSRect(x: cellFrame.minX, y: cellFrame.maxY - 1, width: cellFrame.width, height: 1).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Theme.font(12),
            .foregroundColor: Theme.columnHeaderText,
            .paragraphStyle: paragraph,
        ]
        let text = stringValue as NSString
        let height = text.size(withAttributes: attributes).height
        text.draw(in: NSRect(x: cellFrame.minX + 6, y: cellFrame.midY - height / 2, width: cellFrame.width - 12, height: height), withAttributes: attributes)
    }
}

private final class DataCellView: NSTableCellView {
    private let primary = NSTextField.label()
    private let secondary = NSTextField.label(font: Theme.font(10.5), color: Theme.textSecondary)
    private let stack = NSStackView()
    private var background: NSColor?

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        stack.orientation = .vertical
        stack.spacing = 1
        stack.addArrangedSubview(primary)
        stack.addArrangedSubview(secondary)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        primary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        secondary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func apply(_ content: CellContent, alignment: NSTextAlignment) {
        primary.stringValue = content.text
        primary.textColor = content.color
        primary.font = content.font
        primary.alignment = alignment
        secondary.isHidden = content.secondaryText == nil
        secondary.stringValue = content.secondaryText ?? ""
        secondary.textColor = content.secondaryColor
        secondary.alignment = alignment
        stack.alignment = alignment == .right ? .trailing : .leading
        if background != content.background {
            background = content.background
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if let background {
            background.setFill()
            bounds.fill()
        }
    }
}
