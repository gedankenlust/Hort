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
        }
        .frame(minWidth: 1000, minHeight: 600)
        .background(Theme.Colors.background)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeInOut(duration: 0.45)) { booting = false }
            }
        }
    }

    private var effectiveLocale: Locale {
        if settings.language == "system" { return .current }
        return Locale(identifier: settings.language)
    }
}

#Preview {
    ContentView()
}
