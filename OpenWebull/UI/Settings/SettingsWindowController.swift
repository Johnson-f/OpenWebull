import AppKit

final class SettingsWindowController: NSWindowController {
    private let env: AppEnvironment
    private let speedLabel = NSTextField.label(font: Theme.numberFont(12), alignment: .right)
    private let slider = NSSlider(value: 1, minValue: 0.25, maxValue: 5, target: nil, action: nil)

    init(env: AppEnvironment) {
        self.env = env
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        window.title = "Settings"
        super.init(window: window)
        buildContent()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func buildContent() {
        slider.target = self
        slider.action = #selector(speedChanged)
        slider.doubleValue = env.market.speed
        slider.translatesAutoresizingMaskIntoConstraints = false

        let resetButton = NSButton(title: "Reset Paper Account", target: self, action: #selector(resetAccount))
        let note = NSTextField.label(
            "All quotes, news and fills are produced locally by the simulator. No real market data or brokerage is involved.",
            font: Theme.font(11),
            color: .secondaryLabelColor
        )
        note.maximumNumberOfLines = 0
        note.lineBreakMode = .byWordWrapping

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Market volatility:"), slider, speedLabel],
            [NSTextField(labelWithString: "Paper account:"), resetButton, NSGridCell.emptyContentView],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 14
        grid.column(at: 2).width = 44

        let content = NSView()
        content.addSubviews(grid, note)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            slider.widthAnchor.constraint(equalToConstant: 200),
            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 20),
            note.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            note.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            note.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
        ])
        window?.contentView = content
        speedChanged()
    }

    @objc private func speedChanged() {
        env.market.speed = slider.doubleValue
        speedLabel.stringValue = String(format: "%.2f×", slider.doubleValue)
    }

    @objc private func resetAccount() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Reset the paper account?"
        alert.informativeText = "All positions and order history will be cleared and cash reset to $100,000."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.env.broker.reset()
            }
        }
    }
}
