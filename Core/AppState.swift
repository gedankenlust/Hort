import Foundation
import Combine

/// Shared navigation and selection state, so menu commands (defined at the App
/// scene level) and the views can drive the same UI. Transient intents (focus
/// search, export) are exposed as monotonically increasing tokens that views
/// observe via onChange.
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var selection: SidebarSelection = .inbox
    @Published var selectedMemories: Set<UUID> = []
    @Published var showingSettings = false
    @Published var showingAsk = false

    @Published private(set) var focusSearchToken = 0
    @Published private(set) var exportToken = 0
    @Published private(set) var selectAllToken = 0

    private init() {}

    func navigate(to selection: SidebarSelection) {
        self.selection = selection
    }

    func focusSearch() { focusSearchToken &+= 1 }

    func requestExport() { exportToken &+= 1 }

    /// Signals the feed to select every currently shown card.
    func selectAll() { selectAllToken &+= 1 }

    /// Reveals a specific memory: switches to "All" (so it's in the feed) and
    /// selects it. Used when opening a RAG answer's source card. Selecting after
    /// the section change, since switching sections clears the selection.
    func reveal(_ id: UUID) {
        if selection != .all {
            selection = .all
            DispatchQueue.main.async { self.selectedMemories = [id] }
        } else {
            selectedMemories = [id]
        }
    }

    func deleteSelected() {
        guard !selectedMemories.isEmpty else { return }
        MemoryEngine.shared.delete(ids: selectedMemories)
        selectedMemories.removeAll()
    }
}
