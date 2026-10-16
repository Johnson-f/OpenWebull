import AppKit

/// Bottom strip: data-source note on the left; refresh and Eastern Time on the right.
final class StatusBarView: FillView {
    static let height: CGFloat = 30

    var onRefresh: (() -> Void)?

    private let clockLabel = NSTextField.label(font: Theme.numberFont(13), color: Theme.textSecondary, alignment: .right)

    init() {
        super.init(color: Theme.statusBarBackground)
        borderEdges = [.top]
        let source = NSTextField.label("Simulated market data · Paper trading", font: Theme.font(12.5), color: Theme.textTertiary)
        let refresh = IconButton(symbol: "arrow.clockwise", size: 13, tooltip: "Refresh", target: self, action: #selector(refreshClicked))
        refresh.inactiveTint = Theme.textSecondary
        let left = Self.divider()
        let right = Self.divider()
        addSubviews(source, left, refresh, right, clockLabel)
        NSLayoutConstraint.activate([
            source.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            source.centerYAnchor.constraint(equalTo: centerYAnchor),
            clockLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -60),
            clockLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: clockLabel.leadingAnchor, constant: -12),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            refresh.trailingAnchor.constraint(equalTo: right.leadingAnchor, constant: -10),
            refresh.centerYAnchor.constraint(equalTo: centerYAnchor),
            left.trailingAnchor.constraint(equalTo: refresh.leadingAnchor, constant: -10),
            left.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func update(now: Date) {
        clockLabel.stringValue = "Eastern Time: \(Format.easternTimestamp(now))"
    }

    private static func divider() -> NSView {
        let line = FillView(color: NSColor(hex: 0x3A3A3A))
        line.widthAnchor.constraint(equalToConstant: 1).isActive = true
        line.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return line
    }

    @objc private func refreshClicked() { onRefresh?() }
}
