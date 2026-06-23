import Foundation
import Combine

class ScreenshotMonitor {
    static let shared = ScreenshotMonitor()
    
    private var folderWatcher: DispatchSourceFileSystemObject?
    private let fileManager = FileManager.default
    private var knownFiles: Set<String> = []
    
    let onNewScreenshot = PassthroughSubject<MemoryObject, Never>()
    
    private init() {
        let desktopURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        if let files = try? fileManager.contentsOfDirectory(atPath: desktopURL.path) {
            knownFiles = Set(files)
        }
    }
    
    func start() {
        let desktopURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        let descriptor = open(desktopURL.path, O_EVTONLY)
        guard descriptor != -1 else { return }
        
        folderWatcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        
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
    }
    
    private func checkForNewFiles() {
        let desktopURL = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
        guard let currentFiles = try? fileManager.contentsOfDirectory(atPath: desktopURL.path) else { return }
        
        let newFiles = Set(currentFiles).subtracting(knownFiles)
        for fileName in newFiles {
            let isScreenshot = fileName.contains("Screenshot") || fileName.contains("Bildschirmfoto")
            let isHidden = fileName.hasPrefix(".")
            if isScreenshot && !isHidden && (fileName.hasSuffix(".png") || fileName.hasSuffix(".jpg")) {
                let fileURL = desktopURL.appendingPathComponent(fileName)
                // Screenshots may still be flushing to disk when the FS event
                // fires; defer thumbnail generation briefly so the file is whole.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
                    var obj = MemoryObject(type: .screenshot, content: fileURL.path)
                    obj.preview = fileName
                    obj.thumbnailPath = ImageStore.thumbnail(fromFile: fileURL.path, id: obj.id)
                    self?.onNewScreenshot.send(obj)
                }
            }
        }
        knownFiles = Set(currentFiles)
    }
}
