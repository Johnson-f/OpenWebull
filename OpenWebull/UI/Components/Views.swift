import AppKit

/// A layer-backed view with a solid fill and optional hairline borders.
class FillView: NSView {
    var fillColor: NSColor {
        didSet { needsDisplay = true }
    }

    var borderEdges: NSRectEdge.Set = [] {
        didSet { needsDisplay = true }
    }

    var borderColor = Theme.separator

    init(color: NSColor = Theme.panelBackground) {
        fillColor = color
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var wantsUpdateLayer: Bool { borderEdges.isEmpty }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
    }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        bounds.fill()
        borderColor.setFill()
        if borderEdges.contains(.top) { NSRect(x: 0, y: isFlipped ? 0 : bounds.maxY - 1, width: bounds.width, height: 1).fill() }
        if borderEdges.contains(.bottom) { NSRect(x: 0, y: isFlipped ? bounds.maxY - 1 : 0, width: bounds.width, height: 1).fill() }
        if borderEdges.contains(.left) { NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill() }
        if borderEdges.contains(.right) { NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill() }
    }
}

/// Top-anchored document view for scrollable forms.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

extension NSRectEdge {
    struct Set: OptionSet {
        let rawValue: Int
        static let top = Set(rawValue: 1)
        static let bottom = Set(rawValue: 2)
        static let left = Set(rawValue: 4)
        static let right = Set(rawValue: 8)
    }
}

extension NSTextField {
    static func label(
        _ text: String = "",
        font: NSFont = Theme.font(12),
        color: NSColor = Theme.textPrimary,
        alignment: NSTextAlignment = .left
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func numberInput(placeholder: String, fractionDigits: Int) -> NSTextField {
        let field = NSTextField()
        field.placeholderString = placeholder
        field.font = Theme.numberFont(13)
        field.alignment = .right
        field.bezelStyle = .roundedBezel
        field.translatesAutoresizingMaskIntoConstraints = false
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        formatter.usesGroupingSeparator = false
        field.formatter = formatter
        return field
    }
}

extension NSView {
    func pinEdges(to other: NSView, insets: NSEdgeInsets = NSEdgeInsetsZero) {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: other.leadingAnchor, constant: insets.left),
            trailingAnchor.constraint(equalTo: other.trailingAnchor, constant: -insets.right),
            topAnchor.constraint(equalTo: other.topAnchor, constant: insets.top),
            bottomAnchor.constraint(equalTo: other.bottomAnchor, constant: -insets.bottom),
        ])
    }

    func addSubviews(_ views: NSView...) {
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
    }
}

/// A flat button with a solid fill, used for Buy/Sell actions.
final class FilledButton: NSButton {
    var fillColor: NSColor = Theme.accent {
        didSet { needsDisplay = true }
    }

    var titleColor: NSColor = .white {
        didSet { applyTitle() }
    }

    var isActive = true {
        didSet { needsDisplay = true; applyTitle() }
    }

    override var title: String {
        didSet { applyTitle() }
    }

    convenience init(title: String, color: NSColor, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.target = target
        self.action = action
        fillColor = color
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 4
        translatesAutoresizingMaskIntoConstraints = false
        self.title = title
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let base = isActive ? fillColor : Theme.raisedBackground
        layer?.backgroundColor = (isHighlighted ? base.blended(withFraction: 0.2, of: .black) ?? base : base).cgColor
    }

    private func applyTitle() {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .foregroundColor: isActive ? titleColor : Theme.textSecondary,
            .font: Theme.font(13, .semibold),
        ])
    }
}

extension NSPopUpButton {
    static func make(items: [String], target: AnyObject?, action: Selector?) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.addItems(withTitles: items)
        button.controlSize = .small
        button.font = Theme.font(12)
        button.target = target
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

extension NSSegmentedControl {
    static func make(labels: [String], target: AnyObject?, action: Selector?) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne, target: target, action: action)
        control.controlSize = .small
        control.font = Theme.font(11, .medium)
        control.selectedSegment = 0
        control.translatesAutoresizingMaskIntoConstraints = false
        return control
    }
}
