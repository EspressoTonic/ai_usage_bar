import SwiftUI
import Charts
import UsageCore

struct QuotaHistoryView: View {
    let points: [QuotaPoint]
    let tint: Color
    private var rangeLabel: String {
        let first = points.first?.capturedAt.formatted(date: .abbreviated, time: .shortened) ?? ""
        let last = points.last?.capturedAt.formatted(date: .omitted, time: .shortened) ?? ""
        return "Current window · " + first + " – " + last
    }
    var body: some View {
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 3) {
                Chart(points) { point in
                    LineMark(x: .value("Time", point.capturedAt), y: .value("Remaining", 100 - point.usedPercent))
                        .foregroundStyle(tint)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 34)
                .accessibilityLabel("Remaining quota history in this reset window")
                Text(rangeLabel)
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.leading, 56)
        }
    }
}
