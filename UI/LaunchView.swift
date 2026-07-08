import SwiftUI

/// A brief, restrained boot sequence: the Hort mark scales and glows in, the
/// wordmark and a thin scan line follow, then the whole thing fades to reveal
/// the dashboard. Calm and restrained — no spinners, no noise.
struct LaunchView: View {
    @State private var markIn = false
    @State private var textIn = false
    @State private var lineWidth: CGFloat = 0
    @State private var lineGlowing = false

    var body: some View {
        ZStack {
            HortColors.background.ignoresSafeArea()

            VStack(spacing: HortSpacing.lg) {
                if let logoURL = Bundle.main.url(forResource: "Logo Hort Icon", withExtension: "png", subdirectory: "Assets"),
                   let image = NSImage(contentsOf: logoURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .shadow(color: HortColors.accent.opacity(0.4), radius: 20)
                        .scaleEffect(markIn ? 1 : 0.9)
                        .opacity(markIn ? 1 : 0)
                } else {
                    RoundedRectangle(cornerRadius: HortRadius.xl, style: .continuous)
                        .fill(HortColors.accent)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(HortColors.background)
                        )
                        .shadow(color: HortColors.accent.opacity(0.55), radius: 24)
                        .scaleEffect(markIn ? 1 : 0.82)
                        .opacity(markIn ? 1 : 0)
                }

                VStack(spacing: HortSpacing.sm) {
                    if Bundle.main.url(forResource: "Logo Hort Icon", withExtension: "png", subdirectory: "Assets") == nil {
                        Text("Hort")
                            .font(HortTypography.display(size: HortTypography.Size.title))
                            .foregroundColor(HortColors.textPrimary)
                    }

                    Rectangle()
                        .fill(HortColors.accent)
                        .frame(width: lineWidth, height: 2)
                        .opacity(0.8)
                        .shadow(color: HortColors.accent.opacity(lineGlowing ? 0.9 : 0),
                                radius: lineGlowing ? 10 : 0)

                    Text(L("onboarding.status"))
                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                        .tracking(statusTracking)
                        .foregroundColor(HortColors.textTertiary)
                        .frame(width: Self.targetWidth)
                }
                .opacity(textIn ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { markIn = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) { textIn = true }
            withAnimation(.easeInOut(duration: 0.7).delay(0.3)) { lineWidth = 160 }
            // Glow ramps up as the scan line finishes growing, landing right as
            // ContentView begins fading the whole boot screen out.
            withAnimation(.easeOut(duration: 0.3).delay(0.75)) { lineGlowing = true }
        }
    }

    /// Boot-screen width to match — the logo and the scan line above it.
    private static let targetWidth: CGFloat = 160

    /// Per-character letter-spacing that stretches "Ready"/"Bereit" to exactly
    /// `targetWidth`, so the status line lines up with the logo and scan line
    /// above it instead of sitting narrower and off-center-looking.
    private var statusTracking: CGFloat {
        let text = L("onboarding.status")
        guard !text.isEmpty else { return 2.5 }
        let font = NSFont.monospacedSystemFont(ofSize: HortTypography.Size.caption, weight: .medium)
        let naturalWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let extra = Self.targetWidth - naturalWidth
        let gaps = max(text.count - 1, 1)
        return max(0, extra / CGFloat(gaps))
    }
}
