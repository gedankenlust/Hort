import Foundation
import Combine
import ServiceManagement

struct Board: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var colorHex: String?
    var folders: [String] = []
}

/// User-controlled capture and privacy settings, persisted in UserDefaults.
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Whether passive capture is running at all.
    @Published var captureEnabled: Bool {
        didSet { defaults.set(captureEnabled, forKey: Keys.captureEnabled) }
    }

    /// Skip clipboard items marked concealed/transient (e.g. password managers).
    @Published var ignoreConcealed: Bool {
        didSet { defaults.set(ignoreConcealed, forKey: Keys.ignoreConcealed) }
    }

    /// Bundle identifiers of apps whose clipboard activity is never captured.
    @Published var excludedBundleIDs: Set<String> {
        didSet { defaults.set(Array(excludedBundleIDs), forKey: Keys.excludedBundleIDs) }
    }

    /// User-created boards, in display order. Empty by default — users make
    /// their own.
    @Published var boards: [Board] {
        didSet {
            if let encoded = try? JSONEncoder().encode(boards) {
                defaults.set(encoded, forKey: Keys.boards)
            }
        }
    }

    /// Whether local AI integration (Ollama) is enabled.
    @Published var aiEnabled: Bool {
        didSet { defaults.set(aiEnabled, forKey: Keys.aiEnabled) }
    }

    /// The name of the local Ollama model to use.
    @Published var aiModel: String {
        didSet { defaults.set(aiModel, forKey: Keys.aiModel) }
    }

    /// Whether background AI analysis (Autopilot) is enabled.
    @Published var aiAutopilot: Bool {
        didSet { defaults.set(aiAutopilot, forKey: Keys.aiAutopilot) }
    }

    /// Whether the local semantic index (embeddings) and "Ask your memory" are
    /// enabled. Requires Ollama; off by default like the other AI features.
    @Published var semanticEnabled: Bool {
        didSet { defaults.set(semanticEnabled, forKey: Keys.semanticEnabled) }
    }

    /// The local Ollama model used to compute embeddings.
    @Published var embeddingModel: String {
        didSet { defaults.set(embeddingModel, forKey: Keys.embeddingModel) }
    }

    /// User language preference: "system", "en", or "de".
    @Published var language: String {
        didSet { defaults.set(language, forKey: Keys.language) }
    }

    /// Whether Hort registers itself as a login item (macOS Login Items, via
    /// SMAppService — not persisted in UserDefaults, the source of truth is
    /// SMAppService's own registration state).
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Error toggling launch at login: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    /// Seeded with common password managers so secrets are excluded out of the box.
    static let defaultExcludedBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "io.enpass.Enpass-Desktop",
        "com.keepassxc.keepassxc"
    ]

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let captureEnabled = "captureEnabled"
        static let ignoreConcealed = "ignoreConcealed"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let boards = "boards"
        static let aiEnabled = "aiEnabled"
        static let aiModel = "aiModel"
        static let aiAutopilot = "aiAutopilot"
        static let semanticEnabled = "semanticEnabled"
        static let embeddingModel = "embeddingModel"
        static let language = "language"
    }

    private init() {
        language = defaults.string(forKey: Keys.language) ?? "system"
        captureEnabled = defaults.object(forKey: Keys.captureEnabled) as? Bool ?? true
        ignoreConcealed = defaults.object(forKey: Keys.ignoreConcealed) as? Bool ?? true
        if let stored = defaults.array(forKey: Keys.excludedBundleIDs) as? [String] {
            excludedBundleIDs = Set(stored)
        } else {
            excludedBundleIDs = SettingsStore.defaultExcludedBundleIDs
        }
        
        // Load & Migrate Boards
        if let storedData = defaults.data(forKey: Keys.boards),
           let decoded = try? JSONDecoder().decode([Board].self, from: storedData) {
            boards = decoded
        } else if let oldBoards = defaults.array(forKey: Keys.boards) as? [String] {
            let migrated = oldBoards.map { Board(name: $0) }
            boards = migrated
            if let encoded = try? JSONEncoder().encode(migrated) {
                defaults.set(encoded, forKey: Keys.boards)
            }
        } else {
            boards = []
        }
        
        aiEnabled = defaults.object(forKey: Keys.aiEnabled) as? Bool ?? false
        aiModel = defaults.string(forKey: Keys.aiModel) ?? "llama3"
        aiAutopilot = defaults.object(forKey: Keys.aiAutopilot) as? Bool ?? false
        semanticEnabled = defaults.object(forKey: Keys.semanticEnabled) as? Bool ?? false
        embeddingModel = defaults.string(forKey: Keys.embeddingModel) ?? "nomic-embed-text:latest"
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func addBoard(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !boards.contains(where: { $0.name == trimmed }) else { return }
        boards.append(Board(name: trimmed))
    }

    func removeBoard(_ name: String) {
        boards.removeAll { $0.name == name }
    }

    func renameBoard(_ old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old, !boards.contains(where: { $0.name == trimmed }) else { return }
        if let index = boards.firstIndex(where: { $0.name == old }) {
            boards[index].name = trimmed
        } else {
            boards.append(Board(name: trimmed))
        }
    }

    func changeBoardColor(_ name: String, to colorHex: String?) {
        if let index = boards.firstIndex(where: { $0.name == name }) {
            boards[index].colorHex = colorHex
            // Re-assign to trigger didSet publisher
            boards = boards
        }
    }

    func addFolder(to boardName: String, folderName: String) {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let index = boards.firstIndex(where: { $0.name == boardName }) {
            if !boards[index].folders.contains(trimmed) {
                boards[index].folders.append(trimmed)
                boards = boards
            }
        }
    }

    func removeFolder(from boardName: String, folderName: String) {
        if let index = boards.firstIndex(where: { $0.name == boardName }) {
            boards[index].folders.removeAll { $0 == folderName }
            boards = boards
        }
    }
}
