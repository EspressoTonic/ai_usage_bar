import SwiftUI
import UsageCore

struct QuotaWindowView: View {
    let window: QuotaWindow
    let tint: Color
    var muted = false
    var capturedAt: Date? = nil
    var showPace = false
    private var pace: QuotaPace? {
        guard showPace, !muted, let capturedAt else { return nil }
        return QuotaPace.estimate(window: window, capturedAt: capturedAt)
    }
    private var paceText: String? {
        guard let pace else { return nil }
        if let exhaustion = pace.exhaustionAt, exhaustion > Date() {
            return "Pace estimate: may run out in " + DisplayFormat.interval(to: exhaustion)
        }
        return "Pace estimate: \(Int(pace.projectedUsedPercent.rounded()))% used by reset"
    }

    private var remaining: Double { min(100, max(0, window.remainingPercent)) }
    private var percentage: Int { Int(remaining.rounded()) }
    private var color: Color {
        if muted { return .secondary }
        if remaining <= 10 { return .red }
        if remaining <= 25 { return .orange }
        return tint
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 4)
                if remaining > 0 {
                    Circle().trim(from: 0, to: remaining / 100)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                VStack(spacing: 0) {
                    Text("\(percentage)%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("left").font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(window.label).font(.subheadline).fontWeight(.medium)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(DisplayFormat.reset(window.resetsAt))
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let paceText {
                    Text(paceText).font(.caption2).foregroundStyle(pace?.aheadOfTime == true ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help("Linear estimate from usage since the reported window began. Your future pace can change.")
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.label)
        .accessibilityValue("\(percentage) percent remaining. \(DisplayFormat.reset(window.resetsAt)). \(paceText ?? "")")
    }
}
