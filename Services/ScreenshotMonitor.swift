import Foundation
import Combine

/// Watches the macOS screenshot destination folder for new capture files.
class ScreenshotMonitor: ObservableObject {
    static let shared = ScreenshotMonitor()

    enum AccessState: Equatable {
        case idle
        case watching
        case noAccess
    }

    @Published private(set) var accessState: AccessState = .idle
    @Published private(set) var watchPath: String?

    private var folderWatcher: DispatchSourceFileSystemObject?
    private let fileManager = FileManager.default
    private var knownFiles: Set<String> = []
    /// Files currently waiting for a flush/persist retry — not yet in knownFiles.
    private var pendingFiles: Set<String> = []

    let onNewScreenshot = PassthroughSubject<MemoryObject, Never>()

    private init() {}

    func start() {
        // Idempotent: a second start must not leak another FS watcher.
        stop()

        let folderURL = Self.screenshotFolderURL()
        watchPath = folderURL.path

        // Reseed on every start so files created while paused are never
        // backfilled on resume (privacy: pause means pause).
        if let files = try? fileManager.contentsOfDirectory(atPath: folderURL.path) {
            knownFiles = Set(files)
        } else {
            knownFiles = []
        }
        pendingFiles = []

        let descriptor = open(folderURL.path, O_EVTONLY)
        guard descriptor != -1 else {
            accessState = .noAccess
            return
        }

        accessState = .watching
        folderWatcher = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: .main
        )

        folderWatcher?.setEventHandler { [weak self] in
            self?.checkForNewFiles()
        }

        folderWatcher?.setCancelHandler {
            close(descriptor)
        }

        folderWatcher?.resume()
    }

    func stop() {
        folderWatcher?.cancel()
        folderWatcher = nil
        if accessState != .idle {
            accessState = .idle
        }
    }

    /// Resolves the folder macOS writes screenshots into.
    static func screenshotFolderURL() -> URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        if let location = defaults?.string(forKey: "location"), !location.isEmpty {
            let expanded = (location as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
    }

    /// True when `fileName` looks like a macOS screenshot across common locales.
    static func isScreenshotFileName(_ fileName: String) -> Bool {
        if fileName.hasPrefix(".") { return false }
        let lower = fileName.lowercased()
        let allowedExts = [".png", ".jpg", ".jpeg", ".heic"]
        guard allowedExts.contains(where: { lower.hasSuffix($0) }) else { return false }

        // Localized default prefixes used by macOS screenshot naming.
        let prefixes = [
            "screenshot",
            "bildschirmfoto",
            "capture d’écran",
            "capture d'écran",
            "captura de pantalla",
            "schermata",
            "スクリーンショット",
            "스크린샷",
            "屏幕快照",
            "截屏"
        ]
        return prefixes.contains { lower.hasPrefix($0) || fileName.hasPrefix($0) || lower.contains($0) }
    }

    private func checkForNewFiles() {
        let folderURL = Self.screenshotFolderURL()
        guard let currentFiles = try? fileManager.contentsOfDirectory(atPath: folderURL.path) else { return }
        let onDisk = Set(currentFiles)

        let newFiles = onDisk.subtracting(knownFiles).subtracting(pendingFiles)
        for fileName in newFiles where Self.isScreenshotFileName(fileName) {
            pendingFiles.insert(fileName)
            attemptPersist(fileName: fileName, folderURL: folderURL, attempt: 0)
        }

        // Drop entries that vanished; never mark pending files as known yet.
        knownFiles = onDisk.subtracting(pendingFiles)
        pendingFiles = pendingFiles.intersection(onDisk)
    }

    private func attemptPersist(fileName: String, folderURL: URL, attempt: Int) {
        let fileURL = folderURL.appendingPathComponent(fileName)
        let maxAttempts = 4
        let delay = 0.35 + (0.25 * Double(attempt))

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                DispatchQueue.main.async {
                    self.pendingFiles.remove(fileName)
                }
                return
            }

            // Wait until size is stable so we don't thumbnail a half-written file.
            let size1 = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? -1
            Thread.sleep(forTimeInterval: 0.15)
            let size2 = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? -2
            if size1 != size2 || size1 <= 0 {
                if attempt + 1 < maxAttempts {
                    self.attemptPersist(fileName: fileName, folderURL: folderURL, attempt: attempt + 1)
                } else {
                    DispatchQueue.main.async {
                        self.pendingFiles.remove(fileName)
                        // Leave out of knownFiles so a later FS event can retry.
                    }
                }
                return
            }

            var obj = MemoryObject(type: .screenshot, content: fileURL.path)
            obj.preview = fileName
            let stored = ImageStore.persist(fromFile: fileURL.path, id: obj.id)
            guard stored.asset != nil || stored.thumbnail != nil else {
                if attempt + 1 < maxAttempts {
                    self.attemptPersist(fileName: fileName, folderURL: folderURL, attempt: attempt + 1)
                } else {
                    DispatchQueue.main.async {
                        self.pendingFiles.remove(fileName)
                    }
                }
                return
            }

            obj.content = stored.asset ?? fileURL.path
            obj.thumbnailPath = stored.thumbnail
            obj.metadata["sourcePath"] = fileURL.path

            DispatchQueue.main.async {
                self.pendingFiles.remove(fileName)
                self.knownFiles.insert(fileName)
                self.onNewScreenshot.send(obj)
            }
        }
    }
}
