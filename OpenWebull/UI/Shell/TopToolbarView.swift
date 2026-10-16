import AppKit

/// The window's top strip: brand, page icons, symbol search and the account picker.
final class TopToolbarView: FillView {
    static let height: CGFloat = 38
    /// Leaves room for the window's traffic-light buttons in a full-size content view.
    private static let leadingInset: CGFloat = 84

    var onSelectPage: ((Workspace) -> Void)?
    var onSymbolSearch: ((String) -> Void)?
    var accountMenu: (() -> NSMenu)?

    let searchField = NSSearchField()
    private var pageButtons: [Workspace: IconButton] = [:]
    private let accountButton = NSButton()
    private let completer: SymbolCompleter

    init(instruments: [Instrument]) {
        completer = SymbolCompleter(instruments: instruments)
        super.init(color: Theme.toolbarBackground)

        let mark = NSImageView(image: NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: nil)!)
        mark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        mark.contentTintColor = Theme.textPrimary
        let brand = NSTextField.label("OpenWebull", font: Theme.font(15, .bold), color: Theme.textPrimary)
        let brandDivider = Self.divider()

        let pages = NSStackView()
        pages.spacing = 10
        for workspace in Workspace.toolbarPages {
            let button = IconButton(symbol: workspace.symbolName, size: 16, tooltip: workspace.title, target: self, action: #selector(pageClicked(_:)))
            button.tag = workspace.rawValue
            button.activeTint = Theme.textPrimary
            button.inactiveTint = Theme.icon
            pageButtons[workspace] = button
            pages.addArrangedSubview(button)
        }

        searchField.placeholderAttributedString = NSAttributedString(string: "Search symbols to view in Stocks", attributes: [.foregroundColor: Theme.textTertiary, .font: Theme.font(13)])
        searchField.font = Theme.font(13)
        searchField.textColor = Theme.textPrimary
        searchField.focusRingType = .none
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.sendsWholeSearchString = true
        searchField.target = self
        searchField.action = #selector(searchSubmitted)
        searchField.delegate = completer
        completer.onPick = { [unowned self] symbol in
            onSymbolSearch?(symbol)
            searchField.stringValue = ""
        }
        let searchBox = FillView(color: Theme.toolbarBackground)
        searchBox.layer?.cornerRadius = 4
        searchBox.layer?.borderWidth = 1
        searchBox.layer?.borderColor = Theme.inputBorder.cgColor
        searchBox.addSubviews(searchField)

        let lock = NSImageView(image: NSImage(systemSymbolName: "lock.circle.fill", accessibilityDescription: "Paper trading account")!)
        lock.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        lock.contentTintColor = Theme.icon
        lock.toolTip = "Paper trading account"
        accountButton.isBordered = false
        accountButton.target = self
        accountButton.action = #selector(accountClicked)
        accountButton.attributedTitle = NSAttributedString(string: "Paper Margin (SIM-0001)  ▾", attributes: [.font: Theme.font(13.5), .foregroundColor: Theme.textPrimary])
        let searchDivider = Self.divider()
        let accountDivider = Self.divider()

        addSubviews(mark, brand, brandDivider, pages, searchBox, searchDivider, lock, accountDivider, accountButton)
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.leadingInset),
            mark.centerYAnchor.constraint(equalTo: centerYAnchor),
            brand.leadingAnchor.constraint(equalTo: mark.trailingAnchor, constant: 5),
            brand.centerYAnchor.constraint(equalTo: centerYAnchor),
            brandDivider.leadingAnchor.constraint(equalTo: brand.trailingAnchor, constant: 14),
            brandDivider.centerYAnchor.constraint(equalTo: centerYAnchor),
            pages.leadingAnchor.constraint(equalTo: brandDivider.trailingAnchor, constant: 14),
            pages.centerYAnchor.constraint(equalTo: centerYAnchor),

            accountButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            accountButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            accountDivider.trailingAnchor.constraint(equalTo: accountButton.leadingAnchor, constant: -12),
            accountDivider.centerYAnchor.constraint(equalTo: centerYAnchor),
            lock.trailingAnchor.constraint(equalTo: accountDivider.leadingAnchor, constant: -12),
            lock.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchDivider.trailingAnchor.constraint(equalTo: lock.leadingAnchor, constant: -12),
            searchDivider.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchBox.trailingAnchor.constraint(equalTo: searchDivider.leadingAnchor, constant: -16),
            searchBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchBox.widthAnchor.constraint(equalToConstant: 240),
            searchBox.heightAnchor.constraint(equalToConstant: 25),
            searchBox.leadingAnchor.constraint(greaterThanOrEqualTo: pages.trailingAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 4),
            searchField.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -6),
            searchField.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
        ])
    }

    override var mouseDownCanMoveWindow: Bool { true }

    func select(_ workspace: Workspace) {
        for (candidate, button) in pageButtons {
            button.isActive = candidate == workspace
        }
    }

    private static func divider() -> NSView {
        let line = FillView(color: NSColor(hex: 0x3A3A3A))
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return line
    }

    @objc private func pageClicked(_ sender: NSButton) {
        guard let workspace = Workspace(rawValue: sender.tag) else { return }
        onSelectPage?(workspace)
    }

    @objc private func accountClicked() {
        guard let menu = accountMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: accountButton.bounds.maxY + 6), in: accountButton)
    }

    @objc private func searchSubmitted() {
        guard let symbol = completer.bestMatch(for: searchField.stringValue) else { return }
        onSymbolSearch?(symbol)
        searchField.stringValue = ""
        window?.makeFirstResponder(nil)
    }
}

/// Feeds symbol completions to the search field's field editor.
@MainActor
final class SymbolCompleter: NSObject, NSSearchFieldDelegate {
    var onPick: ((String) -> Void)?
    private let instruments: [Instrument]
    private var isCompleting = false

    init(instruments: [Instrument]) {
        self.instruments = instruments
    }

    func matches(for query: String) -> [Instrument] {
        let needle = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !needle.isEmpty else { return [] }
        let bySymbol = instruments.filter { $0.symbol.hasPrefix(needle) }
        let byName = instruments.filter { !$0.symbol.hasPrefix(needle) && $0.name.uppercased().contains(needle) }
        return bySymbol.sorted { $0.symbol.count < $1.symbol.count } + byName
    }

    func bestMatch(for query: String) -> String? {
        let needle = query.trimmingCharacters(in: .whitespaces).uppercased()
        if instruments.contains(where: { $0.symbol == needle }) { return needle }
        return matches(for: query).first?.symbol
    }

    func controlTextDidChange(_ notification: Notification) {
        guard !isCompleting, let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView else { return }
        isCompleting = true
        editor.complete(nil)
        isCompleting = false
    }

    func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        index.pointee = -1
        return matches(for: textView.string).prefix(12).map(\.symbol)
    }
}
