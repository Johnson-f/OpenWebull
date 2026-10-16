import AppKit

/// A transient pill shown at the top of the window for fills and rejections.
@MainActor
final class ToastPresenter {
    private weak var host: NSView?
    private var current: NSView?
    private var dismissal: Task<Void, Never>?

    init(host: NSView) {
        self.host = host
    }

    func show(_ message: String, color: NSColor) {
        guard let host else { return }
        dismissal?.cancel()
        current?.removeFromSuperview()

        let pill = FillView(color: Theme.raisedBackground)
        pill.layer?.cornerRadius = 16
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = color.withAlphaComponent(0.7).cgColor
        let dot = FillView(color: color)
        dot.layer?.cornerRadius = 4
        let label = NSTextField.label(message, font: Theme.font(13, .medium))
        pill.addSubviews(dot, label)
        host.addSubviews(pill)
        NSLayoutConstraint.activate([
            pill.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            pill.topAnchor.constraint(equalTo: host.topAnchor, constant: 52),
            pill.heightAnchor.constraint(equalToConstant: 32),
            dot.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            dot.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
        ])
        current = pill

        dismissal = Task { [weak pill] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let pill else { return }
            NSAnimationContext.current.duration = 0.25
            pill.animator().alphaValue = 0
            try? await Task.sleep(for: .milliseconds(300))
            pill.removeFromSuperview()
        }
    }
}
