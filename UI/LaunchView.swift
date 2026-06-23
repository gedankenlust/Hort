import SwiftUI

/// A brief, restrained boot sequence: the Hort mark scales and glows in, the
/// wordmark and a thin scan line follow, then the whole thing fades to reveal
/// the dashboard. Calm and tactical — no spinners, no noise.
struct LaunchView: View {
    @State private var markIn = false
    @State private var textIn = false
    @State private var lineWidth: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()

            VStack(spacing: 18) {
                if let logoURL = Bundle.main.url(forResource: "Logo Hort Icon", withExtension: "png", subdirectory: "Assets"),
                   let image = NSImage(contentsOf: logoURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 160, height: 160)
                        .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 20)
                        .scaleEffect(markIn ? 1 : 0.9)
                        .opacity(markIn ? 1 : 0)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.Colors.accent)
                        .frame(width: 64, height: 64)
                        .overlay(
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(Theme.Colors.background)
                        )
                        .shadow(color: Theme.Colors.accent.opacity(0.55), radius: 24)
                        .scaleEffect(markIn ? 1 : 0.82)
                        .opacity(markIn ? 1 : 0)
                }

                VStack(spacing: 10) {
                    if Bundle.main.url(forResource: "Logo Hort Icon", withExtension: "png", subdirectory: "Assets") == nil {
                        Text("Hort")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    Rectangle()
                        .fill(Theme.Colors.accent)
                        .frame(width: lineWidth, height: 2)
                        .opacity(0.8)

                    Text("MEMORY LAYER ONLINE")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.5)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .opacity(textIn ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { markIn = true }
            withAnimation(.easeOut(duration: 0.4).delay(0.25)) { textIn = true }
            withAnimation(.easeInOut(duration: 0.7).delay(0.3)) { lineWidth = 160 }
        }
    }
}
