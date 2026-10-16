import AppKit

/// A minimal line chart with a gradient fill and an optional dashed baseline.
final class SparklineView: NSView {
    var values: [Double] = [] {
        didSet { needsDisplay = true }
    }

    var baseline: Double? {
        didSet { needsDisplay = true }
    }

    var lineColor: NSColor = Theme.accent {
        didSet { needsDisplay = true }
    }

    var showsFill = true
    var lineWidth: CGFloat = 1.5

    override func draw(_ dirtyRect: NSRect) {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return }
        let minValue = min(low, baseline ?? low)
        let maxValue = max(high, baseline ?? high)
        let range = max(maxValue - minValue, .ulpOfOne)
        let inset = bounds.insetBy(dx: 1, dy: 2)

        func point(_ index: Int, _ value: Double) -> NSPoint {
            NSPoint(
                x: inset.minX + inset.width * CGFloat(index) / CGFloat(values.count - 1),
                y: inset.minY + inset.height * CGFloat((value - minValue) / range)
            )
        }

        let line = NSBezierPath()
        for (index, value) in values.enumerated() {
            index == 0 ? line.move(to: point(index, value)) : line.line(to: point(index, value))
        }

        if showsFill {
            let fill = line.copy() as! NSBezierPath
            fill.line(to: NSPoint(x: inset.maxX, y: inset.minY))
            fill.line(to: NSPoint(x: inset.minX, y: inset.minY))
            fill.close()
            NSGradient(starting: lineColor.withAlphaComponent(0.28), ending: lineColor.withAlphaComponent(0.0))?
                .draw(in: fill, angle: -90)
        }

        if let baseline {
            let y = point(0, baseline).y
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: inset.minX, y: y))
            dash.line(to: NSPoint(x: inset.maxX, y: y))
            dash.setLineDash([2, 3], count: 2, phase: 0)
            dash.lineWidth = 1
            Theme.textTertiary.setStroke()
            dash.stroke()
        }

        line.lineWidth = lineWidth
        line.lineJoinStyle = .round
        lineColor.setStroke()
        line.stroke()
    }
}
