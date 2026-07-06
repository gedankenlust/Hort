import SwiftUI

/// Card wrapper providing consistent background, hover, selection, border and shadow.
struct HortCard<Content: View>: View {
    let isSelected: Bool
    let isHovering: Bool
    var cornerRadius: CGFloat = HortSizing.cardRadius
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(isHovering ? HortColors.elevatedHover : HortColors.elevated)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: shadowColor, radius: shadowRadius, y: 4)
    }

    private var borderColor: Color {
        if isSelected { return HortColors.accent }
        if isHovering { return HortColors.borderStrong }
        return HortColors.border
    }

    private var shadowColor: Color {
        .black.opacity(isSelected ? 0.45 : (isHovering ? 0.35 : 0.2))
    }

    private var shadowRadius: CGFloat {
        isSelected ? 14 : (isHovering ? 10 : 5)
    }
}
