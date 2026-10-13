import SwiftUI

/// Card wrapper providing consistent background, hover, selection, border and shadow.
///
/// Shadow radius stays fixed: animating shadow size on hover/selection forces
/// expensive offscreen passes across every visible LazyVGrid cell during scroll.
struct HortCard<Content: View>: View {
    let isSelected: Bool
    let isHovering: Bool
    var cornerRadius: CGFloat = HortSizing.cardRadius
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(isHovering || isSelected ? HortColors.elevatedHover : HortColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
    }

    private var borderColor: Color {
        if isSelected { return HortColors.accent }
        if isHovering { return HortColors.borderStrong }
        return HortColors.border
    }
}
