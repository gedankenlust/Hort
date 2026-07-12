import Foundation

class FileSystemManager {
    static let shared = FileSystemManager()
    
    let rootURL: URL
    let assetsURL: URL
    let exportsURL: URL
    let thumbnailsURL: URL
    
    private convenience init() {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.init(
            rootURL: appSupportURL.appendingPathComponent("Hort", isDirectory: true),
            migrateLegacyData: true
        )
    }

    /// Creates an isolated store. Tests use this initializer with a temporary
    /// directory so they can never touch the user's real Hort data.
    init(rootURL: URL, migrateLegacyData: Bool = false) {
        self.rootURL = rootURL
        assetsURL = rootURL.appendingPathComponent("assets", isDirectory: true)
        exportsURL = rootURL.appendingPathComponent("exports", isDirectory: true)
        thumbnailsURL = rootURL.appendingPathComponent("thumbnails", isDirectory: true)

        if migrateLegacyData {
            migrateFromLegacyPath()
        }
        setupDirectories()
    }
    
    /// Migrates data from the legacy ~/OpenDock/ path to the new
    /// ~/Library/Application Support/Hort/ location.
    private func migrateFromLegacyPath() {
        let fileManager = FileManager.default
        let legacyRoot = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("OpenDock", isDirectory: true)
        
        // Only migrate if the old folder exists and the new one doesn't yet
        guard fileManager.fileExists(atPath: legacyRoot.path),
              !fileManager.fileExists(atPath: rootURL.path) else { return }
        
        print("📦 Migrating data from ~/OpenDock/ to ~/Library/Application Support/Hort/…")
        do {
            // Create the parent Application Support dir if needed
            try fileManager.createDirectory(
                at: rootURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Move the entire folder
            try fileManager.moveItem(at: legacyRoot, to: rootURL)
            
            // Rename the database file if it exists
            let oldDB = rootURL.appendingPathComponent("database/opendock.sqlite")
            let newDB = rootURL.appendingPathComponent("database/hort.sqlite")
            if fileManager.fileExists(atPath: oldDB.path),
               !fileManager.fileExists(atPath: newDB.path) {
                try fileManager.moveItem(at: oldDB, to: newDB)
            }
            
            print("✔ Migration complete.")
        } catch {
            print("⚠️ Migration failed: \(error). Will create fresh directories.")
        }
    }
    
    private func setupDirectories() {
        let dirs = [rootURL, assetsURL, exportsURL, thumbnailsURL]
        let fileManager = FileManager.default

        for dir in dirs {
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }

        excludeFromBackup(rootURL)
    }

    /// Keeps the capture store (clipboard history, screenshots, the SQLite DB —
    /// all under `rootURL`) out of Time Machine / iCloud backups, so sensitive
    /// local data isn't silently copied off the machine.
    private func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
    
    func saveAsset(_ data: Data, fileName: String) throws -> URL {
        let targetURL = assetsURL.appendingPathComponent(fileName)
        try data.write(to: targetURL)
        return targetURL
    }
    
    func saveThumbnail(_ data: Data, fileName: String) throws -> URL {
        let targetURL = thumbnailsURL.appendingPathComponent(fileName)
        try data.write(to: targetURL)
        return targetURL
    }
}
