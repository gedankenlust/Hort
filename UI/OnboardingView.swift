import SwiftUI

struct OnboardingView: View {
    @ObservedObject private var capture = CaptureEngine.shared
    @State private var pulseGlow = false
    @State private var cursorShowing = false

    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Status header
            VStack(spacing: HortSpacing.lg) {
                HStack(spacing: HortSpacing.sm) {
                    Circle()
                        .fill(HortColors.accent)
                        .frame(width: 8, height: 8)
                        .opacity(pulseGlow ? 1.0 : 0.35)
                        .scaleEffect(pulseGlow ? 1.3 : 0.9)
                    Text("onboarding.status")
                        .font(HortTypography.technical(size: HortTypography.Size.caption))
                        .tracking(1.5)
                        .foregroundColor(HortColors.accent)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        pulseGlow = true
                    }
                }

                Text("onboarding.title")
                    .font(HortTypography.display(size: HortTypography.Size.largeTitle))
                    .foregroundColor(HortColors.textPrimary)

                Text("onboarding.subtitle")
                    .font(HortTypography.primary(size: HortTypography.Size.bodySmall))
                    .foregroundColor(HortColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.bottom, HortSpacing.xxl)

            // 3-Step Operations Guide
            HStack(spacing: HortSpacing.xl) {
                onboardingStep(
                    stepNumber: "01",
                    title: "onboarding.step1.title",
                    icon: "tray.and.arrow.down",
                    description: "onboarding.step1.desc"
                )

                onboardingStep(
                    stepNumber: "02",
                    title: "onboarding.step2.title",
                    icon: "square.grid.2x2",
                    description: "onboarding.step2.desc"
                )

                onboardingStep(
                    stepNumber: "03",
                    title: "onboarding.step3.title",
                    icon: "square.and.arrow.up",
                    description: "onboarding.step3.desc"
                )
            }
            .padding(.horizontal, HortSpacing.xxl)
            .frame(maxWidth: 960)

            Spacer()

            // Primary CTA
            HortButton(
                title: capture.isCapturing ? "onboarding.stop_capture" : "onboarding.start_capture",
                icon: capture.isCapturing ? "pause.fill" : "play.fill",
                style: capture.isCapturing ? .secondary : .primary
            ) { capture.toggle() }
            .frame(maxWidth: 240)
            .padding(.bottom, HortSpacing.lg)

            // Awaiting status
            HStack(spacing: HortSpacing.xs) {
                Text("onboarding.awaiting")
                Text(cursorShowing ? "_" : " ")
                    .foregroundColor(HortColors.accent)
            }
            .font(HortTypography.technical(size: HortTypography.Size.bodySmall))
            .foregroundColor(HortColors.textTertiary)
            .padding(.bottom, HortSpacing.xxl)
            .onReceive(timer) { _ in
                cursorShowing.toggle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HortColors.background)
    }

    @ViewBuilder
    private func onboardingStep(stepNumber: String, title: String, icon: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: HortSpacing.md) {
            HStack {
                Text(stepNumber)
                    .font(HortTypography.technical(size: HortTypography.Size.caption))
                    .foregroundColor(HortColors.accent)
                    .padding(.horizontal, HortSpacing.sm)
                    .padding(.vertical, HortSpacing.xs)
                    .background(HortColors.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: HortRadius.small, style: .continuous))

                Spacer()

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(HortColors.textSecondary)
            }

            Text(LocalizedStringKey(title))
                .font(HortTypography.label(size: HortTypography.Size.headline))
                .foregroundColor(HortColors.textPrimary)

            Text(LocalizedStringKey(description))
                .font(HortTypography.primary(size: HortTypography.Size.caption))
                .foregroundColor(HortColors.textSecondary)
                .lineSpacing(4)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(HortSpacing.lg)
        .frame(height: 180)
        .background(HortColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HortRadius.large)
                .strokeBorder(HortColors.border, lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingView()
}
