import AppKit

/// Three original monochrome marks. The first and second tracks match the numbers in reading order.
enum MenuQuotaMark: String, CaseIterable, Codable, Identifiable {
    case rails, orbit, stacks
    var id: Self { self }
    var title: String { rawValue.capitalized }
}

enum MenuQuotaArtwork {
    /// A single template image keeps custom glyphs and figures together in MenuBarExtra.
    static func image(mark: MenuQuotaMark, levels: [Int?], text: String?, description: String) -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.black,
        ]
        let label = text.map { NSAttributedString(string: $0, attributes: attributes) }
        let labelSize = label?.size() ?? .zero
        let size = NSSize(width: label == nil ? 18 : 23 + ceil(labelSize.width), height: 18)
        let result = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(mark: mark, levels: levels, in: CGRect(x: 0, y: 0, width: 18, height: 18), color: .black, context: context)
            label?.draw(at: NSPoint(x: 23, y: (size.height - labelSize.height) / 2))
            return true
        }
        result.isTemplate = true
        result.accessibilityDescription = description
        return result
    }

    /// Coordinates are top-left based so the same vector marks can be rendered in previews.
    static func draw(mark: MenuQuotaMark, levels: [Int?], in rect: CGRect, color: NSColor, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / 18, y: rect.height / 18)
        let count = levels.count == 1 ? 1 : 2
        let track = color.withAlphaComponent(levels.isEmpty ? 0.78 : 0.28).cgColor
        let active = color.cgColor
        func ratio(_ index: Int) -> CGFloat? {
            guard index < levels.count, let value = levels[index] else { return nil }
            return CGFloat(min(100, max(0, value))) / 100
        }
        func fill(_ rect: CGRect, radius: CGFloat, with shade: CGColor) {
            guard rect.width > 0, rect.height > 0 else { return }
            let corner = min(radius, rect.width / 2, rect.height / 2)
            context.setFillColor(shade)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
            context.fillPath()
        }
        for index in 0..<count {
            switch mark {
            case .rails:
                let y: CGFloat = count == 1 ? 7 : (index == 0 ? 3.4 : 10.6)
                let rail = CGRect(x: 1, y: y, width: 16, height: 4)
                fill(rail, radius: 2, with: track)
                if let value = ratio(index) {
                    fill(CGRect(x: rail.minX, y: y, width: rail.width * value, height: rail.height), radius: 2, with: active)
                }
            case .orbit:
                let radius: CGFloat = index == 0 ? 7 : 4
                let start = CGFloat.pi * 0.75, sweep = CGFloat.pi * 1.5
                func stroke(_ fraction: CGFloat, with shade: CGColor) {
                    guard fraction > 0 else { return }
                    context.setStrokeColor(shade)
                    context.setLineWidth(1.7)
                    context.setLineCap(.round)
                    context.addArc(center: CGPoint(x: 9, y: 9), radius: radius, startAngle: start,
                                   endAngle: start + sweep * fraction, clockwise: false)
                    context.strokePath()
                }
                stroke(1, with: track)
                if let value = ratio(index) { stroke(value, with: active) }
            case .stacks:
                let x: CGFloat = count == 1 ? 6.5 : (index == 0 ? 2.5 : 10.5)
                let height: CGFloat = index == 0 ? 15 : 11
                let column = CGRect(x: x, y: 16.5 - height, width: 5, height: height)
                fill(column, radius: 2.5, with: track)
                if let value = ratio(index) {
                    fill(CGRect(x: x, y: column.maxY - height * value, width: 5, height: height * value), radius: 2.5, with: active)
                }
            }
        }
    }
}
