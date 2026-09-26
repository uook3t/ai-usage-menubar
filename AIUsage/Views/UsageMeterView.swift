import AppKit
import SwiftUI

/// Shared percentage header and progress track for AI quotas and bounded resources.
struct UsageMeterView: View {
    let title: String
    let usedPercent: Double
    let displayMode: UsageDisplayMode
    let percentText: String
    var warningThreshold: Double = 60
    var criticalThreshold: Double = 85

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(percentText)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(warningTint ?? Color(nsColor: .labelColor))
                    Text(displayMode.valueSuffix)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(0.1))
                    Capsule()
                        .fill(warningTint ?? UsagePalette.normalUsage)
                        .frame(width: geometry.size.width * displayMode.renderedFraction(from: usedPercent))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
    }

    private var warningTint: Color? {
        if usedPercent >= criticalThreshold { return UsagePalette.critical }
        if usedPercent >= warningThreshold { return UsagePalette.warning }
        return nil
    }
}
