import AppKit

/// Text tabs on a gray bar, separated by short dividers; the selected tab gets a lighter cell.
final class TabStripView: FillView {
    static let height: CGFloat = 25

    var titles: [String] = [] {
        didSet { needsDisplay = true }
    }

    var selectedIndex = 0 {
        didSet { needsDisplay = true }
    }

    var onSelect: ((Int) -> Void)?
    /// Shown as a list icon at the trailing edge when set.
    var trailingMenu: (() -> NSMenu?)? {
        didSet { menuButton.isHidden = trailingMenu == nil }
    }

    private let horizontalPadding: CGFloat = 10
    private let titleFont = Theme.font(13)
    private let menuButton = NSButton()

    init() {
        super.init(color: Theme.tabBarBackground)
        menuButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Tab Menu")
        menuButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        menuButton.isBordered = false
        menuButton.contentTintColor = Theme.icon
        menuButton.target = self
        menuButton.action = #selector(showMenu)
        menuButton.isHidden = true
        addSubviews(menuButton)
        NSLayoutConstraint.activate([
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let frames = tabFrames()
        for (index, frame) in frames.enumerated() {
            let isSelected = index == selectedIndex
            if isSelected {
                Theme.tabSelectedBackground.setFill()
                frame.fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: isSelected ? Theme.textPrimary : Theme.textSecondary,
            ]
            let title = titles[index] as NSString
            let size = title.size(withAttributes: attributes)
            title.draw(at: NSPoint(x: frame.minX + horizontalPadding, y: (bounds.height - size.height) / 2), withAttributes: attributes)

            let nextIsSelected = index + 1 == selectedIndex
            if !isSelected, !nextIsSelected {
                Theme.tabDivider.setFill()
                NSRect(x: frame.maxX - 0.5, y: 7, width: 1, height: bounds.height - 14).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = tabFrames().firstIndex(where: { $0.contains(point) }), index != selectedIndex else { return }
        selectedIndex = index
        onSelect?(index)
    }

    private func tabFrames() -> [NSRect] {
        var x: CGFloat = 0
        return titles.map { title in
            let width = (title as NSString).size(withAttributes: [.font: titleFont]).width + horizontalPadding * 2
            defer { x += width }
            return NSRect(x: x, y: 0, width: width, height: bounds.height)
        }
    }

    @objc private func showMenu() {
        guard let menu = trailingMenu?() else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: menuButton.frame.minX, y: menuButton.frame.maxY + 4), in: self)
    }
}

/// Hosts several panels behind a tab strip; only the selected panel is in the view hierarchy,
/// so hidden panels skip their per-tick refresh.
final class TabbedPanelController: NSViewController {
    let panels: [NSViewController]
    let strip = TabStripView()
    private let content = FillView(color: Theme.panelBackground)
    private var current: NSViewController?

    init(panels: [NSViewController], selectedIndex: Int = 0) {
        self.panels = panels
        super.init(nibName: nil, bundle: nil)
        strip.selectedIndex = selectedIndex
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var selectedIndex: Int { strip.selectedIndex }

    override func loadView() {
        let root = FillView(color: Theme.panelBackground)
        root.addSubviews(strip, content)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: root.topAnchor),
            strip.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            strip.heightAnchor.constraint(equalToConstant: TabStripView.height),
            content.topAnchor.constraint(equalTo: strip.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root

        panels.forEach(addChild)
        strip.titles = panels.map { $0.title ?? "" }
        strip.onSelect = { [weak self] index in self?.show(index) }
        show(strip.selectedIndex)
    }

    func show(_ index: Int) {
        guard panels.indices.contains(index) else { return }
        strip.selectedIndex = index
        current?.view.removeFromSuperview()
        let panel = panels[index]
        content.addSubview(panel.view)
        panel.view.pinEdges(to: content)
        current = panel
    }

    func show(title: String) {
        if let index = panels.firstIndex(where: { $0.title == title }) {
            show(index)
        }
    }
}
