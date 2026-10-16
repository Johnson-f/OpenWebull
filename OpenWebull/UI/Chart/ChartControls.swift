import AppKit

/// A borderless SF Symbol button with hover and active states, as used across the toolbars.
final class IconButton: NSButton {
    var isActive = false {
        didSet { applyTint() }
    }

    var activeTint = Theme.accent
    var inactiveTint = Theme.icon
    var showsActiveBackground = false

    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    convenience init(symbol: String, size: CGFloat = 15, tooltip: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        imagePosition = .imageOnly
        isBordered = false
        toolTip = tooltip
        self.target = target
        self.action = action
        wantsLayer = true
        layer?.cornerRadius = 3
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size + 13).isActive = true
        heightAnchor.constraint(equalToConstant: size + 11).isActive = true
        applyTint()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let highlighted = isHovered || (isActive && showsActiveBackground)
        layer?.backgroundColor = highlighted ? Theme.raisedBackground.cgColor : NSColor.clear.cgColor
    }

    private func applyTint() {
        contentTintColor = isActive ? activeTint : inactiveTint
        needsDisplay = true
    }
}

/// A plain text button: gray normally, accent with an underline when selected.
final class TextTabButton: NSButton {
    var isSelected = false {
        didSet { applyStyle() }
    }

    var showsDisclosure = false {
        didSet { applyStyle() }
    }

    /// The visible text; kept separately because `title` reads back the styled string.
    var label = "" {
        didSet { applyStyle() }
    }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        isBordered = false
        self.target = target
        self.action = action
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        label = title
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isSelected else { return }
        Theme.accent.setFill()
        let labelWidth = (label as NSString).size(withAttributes: [.font: Theme.font(13)]).width
        let textStart = (bounds.width - attributedTitle.size().width) / 2
        NSBezierPath(roundedRect: NSRect(x: textStart, y: bounds.height - 3, width: labelWidth, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
    }

    override var isFlipped: Bool { true }

    private func applyStyle() {
        let text = NSMutableAttributedString(string: label, attributes: [
            .font: Theme.font(13),
            .foregroundColor: isSelected ? Theme.accent : Theme.textPrimary,
        ])
        if showsDisclosure {
            text.append(NSAttributedString(string: "  ▾", attributes: [.font: Theme.font(9), .foregroundColor: Theme.textSecondary]))
        }
        attributedTitle = text
        needsDisplay = true
    }
}

/// The bordered strip in the chart's top-left: identity, interval, adjustment, news and alerts.
final class ChartLegendChip: NSView {
    var onNews: (() -> Void)?
    var onAlert: (() -> Void)?

    private let identity = NSTextField.label(font: Theme.font(13))
    private let intervalLabel = NSTextField.label(font: Theme.font(13), color: Theme.textSecondary)
    private var cells: [NSView] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = Theme.separator.cgColor
        layer?.cornerRadius = 2
        layer?.backgroundColor = Theme.panelBackground.cgColor

        let adjusted = NSTextField.label("Adjusted", font: Theme.font(13), color: Theme.textSecondary)
        let news = NSButton(title: "News", target: self, action: #selector(newsClicked))
        news.isBordered = false
        news.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)
        news.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        news.imagePosition = .imageLeading
        news.contentTintColor = Theme.newsOrange
        news.attributedTitle = NSAttributedString(string: "News", attributes: [.font: Theme.font(13), .foregroundColor: Theme.newsOrange])
        let bell = NSButton(image: NSImage(systemSymbolName: "bell.fill", accessibilityDescription: "Price Alert")!, target: self, action: #selector(alertClicked))
        bell.isBordered = false
        bell.contentTintColor = Theme.icon
        bell.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        bell.toolTip = "Set a price alert"

        cells = [identity, intervalLabel, adjusted, news, bell]
        var previous: NSView?
        for (index, cell) in cells.enumerated() {
            addSubviews(cell)
            NSLayoutConstraint.activate([
                cell.centerYAnchor.constraint(equalTo: centerYAnchor),
                cell.leadingAnchor.constraint(equalTo: previous?.trailingAnchor ?? leadingAnchor, constant: previous == nil ? 8 : 16),
            ])
            if let previous, index > 0 {
                let divider = FillView(color: Theme.separator)
                addSubviews(divider)
                NSLayoutConstraint.activate([
                    divider.widthAnchor.constraint(equalToConstant: 1),
                    divider.topAnchor.constraint(equalTo: topAnchor),
                    divider.bottomAnchor.constraint(equalTo: bottomAnchor),
                    divider.leadingAnchor.constraint(equalTo: previous.trailingAnchor, constant: 8),
                ])
            }
            previous = cell
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 26),
            cells.last!.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(symbol: String, name: String, interval: ChartInterval) {
        let text = NSMutableAttributedString(string: symbol, attributes: [.foregroundColor: Theme.textPrimary, .font: Theme.font(13)])
        text.append(NSAttributedString(string: "   \(name.uppercased())", attributes: [.foregroundColor: Theme.textSecondary, .font: Theme.font(13)]))
        identity.attributedStringValue = text
        intervalLabel.stringValue = interval.title
    }

    @objc private func newsClicked() { onNews?() }
    @objc private func alertClicked() { onAlert?() }
}

/// Small grouped toggles at the chart footer's trailing edge.
final class ToggleGroupView: NSView {
    struct Item {
        let title: String
        let isEnabled: Bool
        let tooltip: String
    }

    var onToggle: ((Int, Bool) -> Void)?
    private var buttons: [NSButton] = []
    private var states: [Bool] = []

    init(items: [Item], selected: Set<Int>) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = Theme.raisedBackground.cgColor
        let stack = NSStackView()
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)
        for (index, item) in items.enumerated() {
            let button = NSButton(title: item.title, target: self, action: #selector(toggled(_:)))
            button.isBordered = false
            button.tag = index
            button.isEnabled = item.isEnabled
            button.toolTip = item.tooltip
            button.wantsLayer = true
            button.layer?.cornerRadius = 2
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 38).isActive = true
            button.heightAnchor.constraint(equalToConstant: 20).isActive = true
            buttons.append(button)
            states.append(selected.contains(index))
            stack.addArrangedSubview(button)
        }
        addSubviews(stack)
        stack.pinEdges(to: self)
        buttons.indices.forEach(applyStyle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func toggled(_ sender: NSButton) {
        states[sender.tag].toggle()
        applyStyle(sender.tag)
        onToggle?(sender.tag, states[sender.tag])
    }

    private func applyStyle(_ index: Int) {
        let button = buttons[index]
        let color = !button.isEnabled ? Theme.textTertiary : (states[index] ? Theme.accent : Theme.textSecondary)
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: Theme.font(12.5), .foregroundColor: color])
        button.layer?.backgroundColor = (states[index] ? Theme.controlSelectedBackground : Theme.controlBackground).cgColor
    }
}

enum ChartRange: String, CaseIterable {
    case oneDay = "1D"
    case fiveDays = "5D"
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case fiveYears = "5Y"
    case all = "All"

    var isIntraday: Bool { self == .oneDay || self == .fiveDays }

    var defaultInterval: ChartInterval {
        switch self {
        case .oneDay: .fiveMinutes
        case .fiveDays: .fifteenMinutes
        case .oneMonth, .threeMonths, .sixMonths, .oneYear: .day
        case .fiveYears: .week
        case .all: .month
        }
    }

    static func defaultRange(for interval: ChartInterval) -> ChartRange {
        switch interval {
        case .oneMinute, .fiveMinutes: .oneDay
        case .fifteenMinutes, .thirtyMinutes, .oneHour: .fiveDays
        case .day: .sixMonths
        case .week: .fiveYears
        case .month: .all
        }
    }

    /// Number of bar slots that cover this range at the given interval.
    func slots(for interval: ChartInterval) -> Int {
        let sessionMinutes = Double(MarketSimulator.sessionMinutes)
        let tradingDays: Double = switch self {
        case .oneDay: 1
        case .fiveDays: 5
        case .oneMonth: 21
        case .threeMonths: 63
        case .sixMonths: 126
        case .oneYear: 252
        case .fiveYears: 1_260
        case .all: 100_000
        }
        if interval.isIntraday {
            return Int(ceil(tradingDays * sessionMinutes * 60 / interval.seconds))
        }
        let daysPerBar: Double = switch interval {
        case .week: 5
        case .month: 21
        default: 1
        }
        return Int(ceil(tradingDays / daysPerBar))
    }
}
