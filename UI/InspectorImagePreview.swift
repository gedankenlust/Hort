import SwiftUI
import AppKit

/// Async inspector preview — never decode full assets on the main thread during
/// `body` (that froze tile-to-tile selection when switching image cards).
struct InspectorImagePreview: View {
    let path: String?
    let iconName: String
    let privacyBlurEnabled: Bool

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .privacyBlur(privacyBlurEnabled, radius: PrivacyBlur.image,
                                 disableHitTesting: false)
            } else if path != nil {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                HStack(spacing: HortSpacing.sm) {
                    Image(systemName: iconName)
                        .foregroundColor(HortColors.accent)
                    Text(L("dashboard.image_asset"))
                        .font(HortTypography.primary(size: HortTypography.Size.caption))
                        .foregroundColor(HortColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
            }
        }
        .padding(HortSpacing.md)
        .frame(maxWidth: .infinity)
        .background(HortColors.background)
        .clipShape(RoundedRectangle(cornerRadius: HortRadius.medium, style: .continuous))
        .task(id: path) {
            guard let path else {
                image = nil
                return
            }
            if let cached = ImageCache.shared[path] {
                image = cached
                return
            }
            let loaded = await Task.detached(priority: .userInitiated) {
                ImageCache.loadDisplayImage(at: path, maxPixel: 900)
            }.value
            if let loaded {
                ImageCache.shared[path] = loaded
            }
            image = loaded
        }
    }
}
