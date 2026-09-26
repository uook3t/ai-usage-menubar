import AppKit

@MainActor
enum StackedStatusRenderer {
    static func image(groups: [MenuBarProviderReadings], vpnName: String, vpnFailed: Bool) -> NSImage {
        let titleFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
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
            let titleWidth = (title as NSString).size(withAttributes: [.font: titleFont]).width
            let valueWidth = (value as NSString).size(withAttributes: [.font: numberFont]).width
            return (title, value, ceil(max(titleWidth, valueWidth)) + 4, color)
        }
        let width = entries.reduce(CGFloat(0)) { $0 + $1.2 } + CGFloat(max(entries.count - 1, 0)) * 8
        let image = NSImage(size: NSSize(width: max(width, 20), height: 22), flipped: false) { _ in
            var x: CGFloat = 0
            for (title, value, width, color) in entries {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                (title as NSString).draw(in: NSRect(x: x, y: 11, width: width, height: 11), withAttributes: [
                    .font: titleFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
                ])
                (value as NSString).draw(in: NSRect(x: x, y: 0, width: width, height: 13), withAttributes: [
                    .font: numberFont, .foregroundColor: color, .paragraphStyle: paragraph
                ])
                x += width + 8
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
