import AppKit

/// Pure-black workstation palette. Values were measured from the reference design.
enum Theme {
    // Surfaces
    static let windowBackground = NSColor(hex: 0x000000)
    static let panelBackground = NSColor(hex: 0x000000)
    static let toolbarBackground = NSColor(hex: 0x171717)
    static let tabBarBackground = NSColor(hex: 0x303030)
    static let tabSelectedBackground = NSColor(hex: 0x474747)
    static let panelHeader = tabBarBackground
    static let raisedBackground = NSColor(hex: 0x2B2B2B)
    static let controlBackground = NSColor(hex: 0x2E2E2E)
    static let controlSelectedBackground = NSColor(hex: 0x474747)
    static let selection = NSColor(hex: 0x2B2B2B)
    static let railBackground = NSColor(hex: 0x0C0C0C)
    static let statusBarBackground = NSColor(hex: 0x212121)
    static let countdownBackground = NSColor(hex: 0x00243A)
    static let watermark = NSColor(hex: 0x1A1A1A)

    // Lines
    static let separator = NSColor(hex: 0x2B2B2B)
    static let rowSeparator = NSColor(hex: 0x212121)
    static let columnDivider = NSColor(hex: 0x1C1C1C)
    static let gridLine = NSColor(hex: 0x141414)
    static let tabDivider = NSColor(hex: 0x5A5A5A)
    static let inputBorder = NSColor(hex: 0x464646)

    // Text
    static let textPrimary = NSColor(hex: 0xF0F0F0)
    static let textSecondary = NSColor(hex: 0xB8B8B8)
    static let textTertiary = NSColor(hex: 0x787878)
    static let columnHeaderText = NSColor(hex: 0xA8A8A8)
    static let icon = NSColor(hex: 0xA8A8A8)
    static let railIcon = NSColor(hex: 0x808080)

    // Accents
    static let accent = NSColor(hex: 0x0098F8)
    static let railActive = NSColor(hex: 0x18C0F8)
    static let up = NSColor(hex: 0x07CDA5)
    static let down = NSColor(hex: 0xF1AA46)
    static let warning = NSColor(hex: 0xF1AA46)
    static let newsOrange = NSColor(hex: 0xE07020)
    static let badge = NSColor(hex: 0xF8B040)

    // Chart
    static let candleUp = NSColor(hex: 0x0DB787)
    static let candleDown = NSColor(hex: 0xF8F8F8)
    static let volumeUp = NSColor(hex: 0x0DB787)
    static let volumeDown = NSColor(hex: 0xEB9D2E)
    static let volumeAverage = NSColor(hex: 0x3F89FF)
    static let axisText = NSColor(hex: 0x787878)
    static let movingAverageColors = [
        NSColor(hex: 0x857FEE),
        NSColor(hex: 0x80B8C0),
        NSColor(hex: 0xA8D8A8),
        NSColor(hex: 0xE0A868),
    ]

    static func trendColor(_ value: Double) -> NSColor {
        if value > 0 { return up }
        if value < 0 { return down }
        return textPrimary
    }

    static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func numberFont(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .monospacedDigitSystemFont(ofSize: size, weight: weight)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
