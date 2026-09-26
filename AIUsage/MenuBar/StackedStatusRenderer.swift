import AppKit

@MainActor
enum StackedStatusRenderer {
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
            var color = NSColor.labelColor
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
        image(entries: [Entry(title: name, value: value, color: .labelColor)])
    }

    private struct Entry {
        let title: String
        let value: String
        let color: NSColor
    }

    private static func image(entries: [Entry]) -> NSImage {
        let titleFont = NSFont.systemFont(ofSize: 7, weight: .light)
        let numberFont = NSFont.systemFont(ofSize: 12, weight: .regular)
        let padding: CGFloat = 2
        let spacing: CGFloat = 2
        let widths = entries.map { entry in
            let titleWidth = (entry.title as NSString).size(withAttributes: [.font: titleFont]).width
            let valueWidth = (entry.value as NSString).size(withAttributes: [.font: numberFont]).width
            return max(31, ceil(max(titleWidth, valueWidth)))
        }
        let width = widths.reduce(0, +) + padding * 2 + CGFloat(max(entries.count - 1, 0)) * spacing
        let image = NSImage(size: NSSize(width: max(width, 20), height: 22), flipped: false) { _ in
            var x = padding
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            for (entry, width) in zip(entries, widths) {
                (entry.title as NSString).draw(in: NSRect(x: x, y: 14, width: width, height: 7), withAttributes: [
                    .font: titleFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
                ])
                (entry.value as NSString).draw(in: NSRect(x: x, y: 3, width: width, height: 13), withAttributes: [
                    .font: numberFont, .foregroundColor: entry.color, .paragraphStyle: paragraph
                ])
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
        image?.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    }

    // Keep the whole status item clickable by its owning NSStatusBarButton.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
