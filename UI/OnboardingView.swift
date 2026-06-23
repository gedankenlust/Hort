import SwiftUI

struct OnboardingView: View {
    @State private var pulseGlow = false
    @State private var cursorShowing = false
    
    private let timer = Timer.publish(every: 0.6, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Cyberdeck Wordmark & Status Header
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Circle()
                        .fill(Theme.Colors.accent)
                        .frame(width: 8, height: 8)
                        .opacity(pulseGlow ? 1.0 : 0.35)
                        .scaleEffect(pulseGlow ? 1.3 : 0.9)
                    Text("onboarding.status")
                        .font(Theme.Fonts.technical(size: 11))
                        .tracking(1.5)
                        .foregroundColor(Theme.Colors.accent)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        pulseGlow = true
                    }
                }
                
                Text("onboarding.title")
                    .font(Theme.Fonts.label(28, weight: .bold))
                    .foregroundColor(Theme.Colors.textPrimary)
                
                Text("onboarding.subtitle")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.bottom, 48)
            
            // 3-Step Operations Guide
            HStack(spacing: 20) {
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
            .padding(.horizontal, 40)
            .frame(maxWidth: 960)
            
            Spacer()
            
            // Terminal Awaiting Status
            HStack(spacing: 4) {
                Text("onboarding.awaiting")
                Text(cursorShowing ? "_" : " ")
                    .foregroundColor(Theme.Colors.accent)
            }
            .font(Theme.Fonts.technical(size: 12))
            .foregroundColor(Theme.Colors.textTertiary)
            .padding(.bottom, 40)
            .onReceive(timer) { _ in
                cursorShowing.toggle()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
    
    @ViewBuilder
    private func onboardingStep(stepNumber: String, title: String, icon: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(stepNumber)
                    .font(Theme.Fonts.technical(size: 11))
                    .foregroundColor(Theme.Colors.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.accentSoft)
                    .cornerRadius(4)
                
                Spacer()
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            
            Text(LocalizedStringKey(title))
                .font(Theme.Fonts.label(15, weight: .semibold))
                .foregroundColor(Theme.Colors.textPrimary)
            
            Text(LocalizedStringKey(description))
                .font(.system(size: 12))
                .foregroundColor(Theme.Colors.textSecondary)
                .lineSpacing(4)
                .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(height: 180)
        .background(Theme.Colors.elevated)
        .cornerRadius(Theme.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cornerRadius)
                .strokeBorder(Theme.Colors.border, lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingView()
}
