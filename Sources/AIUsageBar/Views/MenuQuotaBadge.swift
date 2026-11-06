import SwiftUI
import UsageCore

struct MenuQuotaBadge: View, Equatable {
    let presentation: MenuQuotaPresentation
    let mark: MenuQuotaMark

    var body: some View {
        Image(nsImage: MenuQuotaArtwork.image(mark: mark, levels: presentation.limits.map(\.remaining),
                                             text: presentation.visibleText, description: presentation.accessibilityText))
            .accessibilityLabel(presentation.accessibilityText)
            .help(presentation.accessibilityText)
    }
}
