import SwiftUI

struct ResourceUsageView: View {
    let usage: ResourceUsage
    let displayMode: UsageDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            UsageMeterView(
                title: "流量",
                usedPercent: usage.usedPercent,
                displayMode: displayMode,
                percentText: "\(displayMode.displayedPercent(from: usage.usedPercent).formatted(.number.precision(.fractionLength(1))))%",
                warningThreshold: 80,
                criticalThreshold: 95
            )

            if let day = usage.resetDay {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .foregroundStyle(.tertiary)
                    Text("每月 \(day) 日重置")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                value("已用", usage.used)
                Spacer()
                value("总额度", usage.limit)
                Spacer()
                value("剩余", usage.remaining)
            }
            .padding(.top, 4)

            if usage.overage > 0 {
                Text("已超额 \(usage.formatted(usage.overage))")
                    .foregroundStyle(UsagePalette.critical)
            }
        }
        .font(.caption)
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 11)
    }

    private func value(_ label: String, _ number: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).foregroundStyle(.secondary)
            Text(usage.formatted(number)).monospacedDigit().fontWeight(.medium)
        }
    }
}
