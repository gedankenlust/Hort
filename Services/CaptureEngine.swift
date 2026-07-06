import Foundation
import Combine

class CaptureEngine: ObservableObject {
    static let shared = CaptureEngine()

    /// Whether the monitors are currently running.
    @Published private(set) var isCapturing = false

    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupSubscriptions()
    }

    /// Starts capture unless the user has it disabled in settings.
    func start() {
        guard SettingsStore.shared.captureEnabled else {
            isCapturing = false
            print("Capture Engine: disabled in settings")
            return
        }
        ClipboardMonitor.shared.start()
        ScreenshotMonitor.shared.start()
        isCapturing = true
        print("Capture Engine Started")
    }

    func stop() {
        ClipboardMonitor.shared.stop()
        ScreenshotMonitor.shared.stop()
        isCapturing = false
    }

    /// Pauses capture and remembers the choice across launches.
    func pause() {
        SettingsStore.shared.captureEnabled = false
        stop()
    }

    /// Resumes capture and remembers the choice across launches.
    func resume() {
        SettingsStore.shared.captureEnabled = true
        start()
    }

    func toggle() {
        isCapturing ? pause() : resume()
    }
    
    private func setupSubscriptions() {
        ClipboardMonitor.shared.onNewContent
            .sink { [weak self] object in
                self?.handleNewMemory(object)
            }
            .store(in: &cancellables)
        
        ScreenshotMonitor.shared.onNewScreenshot
            .sink { [weak self] object in
                self?.handleNewMemory(object)
            }
            .store(in: &cancellables)
    }
    
    private func handleNewMemory(_ object: MemoryObject) {
        #if DEBUG
        // Never log captured content itself — it can contain secrets. Length only.
        print("New memory captured: \(object.type) (\(object.content?.count ?? 0) chars)")
        #endif

        // Persist the captured memory
        MemoryEngine.shared.save(object)
        
        let objectID = object.id
        let settings = SettingsStore.shared
        
        if object.type == .image || object.type == .screenshot {
            guard let contentPath = object.content else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                if let ocrText = OCRManager.performOCR(on: contentPath) {
                    #if DEBUG
                    print("OCR success (\(ocrText.count) chars)")
                    #endif
                    DispatchQueue.main.async {
                        MemoryEngine.shared.update(id: objectID) { mut in
                            mut.metadata["ocrText"] = ocrText
                        }
                        self.autopilotAnalyze(objectID: objectID, content: ocrText, settings: settings, imagePath: contentPath)
                        self.enqueueEmbedding(objectID)
                    }
                }
            }
        } else if object.type == .text || object.type == .url {
            autopilotAnalyze(objectID: objectID, content: object.content ?? "", settings: settings)
            enqueueEmbedding(objectID)
        }
    }

    /// Adds the memory to the semantic index queue (no-op when semantic search
    /// is off). Hops to the main actor since EmbeddingIndexer is main-actor bound.
    private func enqueueEmbedding(_ id: UUID) {
        Task { @MainActor in EmbeddingIndexer.shared.enqueue(id) }
    }

    /// Queues a background AI analysis for the memory, if Autopilot is enabled
    /// and there is content to analyze. Analyses run one at a time (see
    /// `AIRuntime`) so bursts of captures don't overload the local model.
    /// Minimum characters before Autopilot bothers analyzing. Tiny clips (e.g.
    /// "WM Doppelpass") give a small model nothing to work with and produce
    /// hallucinated summaries / random tags — no tags beats junk tags. Manual
    /// "Analyze" in the Inspector is unaffected.
    private static let autopilotMinChars = 20

    private func autopilotAnalyze(objectID: UUID, content: String, settings: SettingsStore, imagePath: String? = nil) {
        guard settings.aiEnabled, settings.aiAutopilot else { return }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.autopilotMinChars || imagePath != nil else { return }
        let model = settings.aiModel
        Task { @MainActor in
            AIRuntime.shared.enqueueAutopilot(objectID: objectID, content: trimmed, model: model, imagePath: imagePath)
        }
    }
}
