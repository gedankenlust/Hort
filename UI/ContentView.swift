import SwiftUI

/// The active section in the sidebar. Drives what the dashboard feed shows.
enum SidebarSelection: Hashable {
    case inbox       // unfiled, not archived — the triage pile
    case all         // everything not archived
    case favorites   // starred, not archived
    case archive
    case board(String)
    case folder(board: String, folder: String)
    case tag(String)
}

struct ContentView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var settings = SettingsStore.shared
    @State private var booting = true

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(selection: $app.selection,
                            onOpenSettings: { app.showingSettings = true })
            } content: {
                DashboardFeedView(selection: app.selection,
                             selectedMemories: $app.selectedMemories)
                    .frame(minWidth: 400)
            } detail: {
                InspectorPanel(selectedMemories: $app.selectedMemories)
            }
            .sheet(isPresented: $app.showingSettings) {
                SettingsView()
                    .environment(\.locale, effectiveLocale)
            }
            .sheet(isPresented: $app.showingAsk) {
                AskView()
                    .environment(\.locale, effectiveLocale)
            }
            .onChange(of: app.selection) { _, _ in
                // Clear the selection so the Inspector never shows a card that
                // the newly selected section no longer displays.
                app.selectedMemories.removeAll()
            }

            if booting {
                LaunchView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            if app.undoToastVisible {
                VStack {
                    Spacer()
                    UndoToast()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, HortSpacing.xxl)
                }
                .zIndex(2)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .background(HortColors.background)
        .preferredColorScheme(.dark)
        .background(undoShortcut)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.45)) { booting = false }
            }
        }
    }

    private var undoShortcut: some View {
        Button(action: { app.undoDelete() }) { }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!app.undoToastVisible)
            .opacity(0)
            .allowsHitTesting(false)
    }

    private var effectiveLocale: Locale {
        if settings.language == "system" { return .current }
        return Locale(identifier: settings.language)
    }
}

struct UndoToast: View {
    @ObservedObject private var app = AppState.shared

    var body: some View {
        HStack(spacing: HortSpacing.md) {
            Image(systemName: "trash")
                .font(HortTypography.label(size: 12))
                .foregroundColor(HortColors.danger)
            Text(LocalizedStringKey("toast.deleted"))
                .font(HortTypography.primary(weight: .medium))
                .foregroundColor(HortColors.textPrimary)
            Spacer()
            Button(action: { app.undoDelete() }) {
                Text(LocalizedStringKey("toast.undo"))
                    .font(HortTypography.label(size: 12))
                    .foregroundColor(HortColors.accent)
            }
            .buttonStyle(.plain)
            Button(action: { app.dismissUndo() }) {
                Image(systemName: "xmark")
                    .font(HortTypography.label(size: 10))
                    .foregroundColor(HortColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HortSpacing.lg)
        .padding(.vertical, HortSpacing.md)
        .background(HortColors.elevated)
        .clipShape(RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HortRadius.large, style: .continuous)
                .strokeBorder(HortColors.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 12, y: 4)
        .frame(maxWidth: 340)
    }
}

#Preview {
    ContentView()
}
