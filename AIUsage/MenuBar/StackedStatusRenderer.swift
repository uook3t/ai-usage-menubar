import AppKit

@MainActor
enum StackedStatusRenderer {
    private static let textColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    static func image(groups: [MenuBarProviderReadings], vpnName: String, vpnFailed: Bool) -> NSImage {
        let entries = groups.map { group in
            let title = group.provider == .vpn ? vpnName : group.provider == .claude ? "Claude" : group.provider.displayName
            let readings = group.readings.map { reading -> String in
                let prefix = group.showsMetricLabels ? reading.metric.compactLabel + " " : ""
                if group.provider == .vpn, case .percentage(let value) = reading.value {
                    return value.formatted(.number.precision(.fractionLength(1))) + "%"
                }
                return prefix + (MenuBarPresentation(reading: reading).valueText ?? "--")
            }
            let stale = group.readings.contains(where: \.isStale) || (group.provider == .vpn && vpnFailed)
            let value = (readings.isEmpty ? "--" : readings.joined(separator: " · ")) + (stale ? " !" : "")
            var color = textColor
            if group.provider == .vpn, let reading = group.readings.first,
               case .percentage(let value) = reading.value {
                let used = reading.displayMode == .used ? value : 100 - value
                if used >= 95 { color = .systemRed } else if used >= 80 { color = .systemOrange }
            }
            return Entry(title: title, value: value, color: color)
        }
        return image(entries: entries)
    }

    static func preview(name: String, value: String) -> NSImage {
        image(entries: [Entry(title: name, value: value, color: textColor)])
    }

    private struct Entry {
        let title: String
        let value: String
        let color: NSColor
    }

    private static func image(entries: [Entry]) -> NSImage {
        let titleFont = NSFont.systemFont(ofSize: 7, weight: .light)
        let numberFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let padding: CGFloat = 1
        let spacing: CGFloat = 1
        let widths = entries.map { entry in
            let titleWidth = (entry.title as NSString).size(withAttributes: [.font: titleFont]).width
            let valueWidth = (entry.value as NSString).size(withAttributes: [.font: numberFont]).width
            return ceil(max(titleWidth, valueWidth))
        }
        let width = widths.reduce(0, +) + padding * 2 + CGFloat(max(entries.count - 1, 0)) * spacing
        let image = NSImage(size: NSSize(width: max(width, 1), height: 22), flipped: false) { _ in
            var x = padding
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            for (entry, width) in zip(entries, widths) {
                NSAttributedString(string: entry.title, attributes: [
                    .font: titleFont, .foregroundColor: textColor, .paragraphStyle: paragraph
                ]).draw(with: NSRect(x: x, y: 14, width: width, height: 7))
                NSAttributedString(string: entry.value, attributes: [
                    .font: numberFont, .foregroundColor: entry.color, .paragraphStyle: paragraph
                ]).draw(with: NSRect(x: x, y: 3, width: width, height: 13))
                x += width + spacing
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// Draw directly inside the status button to avoid its automatic image insets.
@MainActor
final class StackedStatusView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            image?.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        image?.recache()
        needsDisplay = true
    }

    // Keep the whole status item clickable by its owning NSStatusBarButton.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
