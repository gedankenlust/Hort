import SwiftUI

/// Consistent section header. Avoids the previous all-caps overload.
struct HortSectionHeader: View {
    let title: LocalizedStringKey
    var action: (() -> Void)? = nil
    var actionIcon: String? = "plus"
    var actionHelp: LocalizedStringKey? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(HortTypography.label(size: HortTypography.Size.caption,
                                           weight: .semibold))
                .foregroundColor(HortColors.textTertiary)
            Spacer()
            if let action, let actionIcon {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(HortColors.textTertiary)
                }
                .buttonStyle(.plain)
                .help(actionHelp ?? "")
            }
        }
    }
}
