import SwiftUI

/// Small removable tag pill.
struct HortTagChip: View {
    let text: String
    var onRemove: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: HortSpacing.xs) {
            Text(text)
                .font(HortTypography.label(size: HortTypography.Size.caption,
                                           weight: .medium))
                .lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
            }
        }
        .foregroundColor(HortColors.accent)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(HortColors.accentSoft)
        .clipShape(Capsule())
        .onHover { isHovering = $0 }
        .opacity(isHovering && onRemove != nil ? 0.85 : 1.0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tag: \(text)")
        .accessibilityHint(onRemove != nil ? "Double tap to remove" : "")
    }
}
