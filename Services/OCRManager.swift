import Foundation
import Vision
import AppKit

enum OCRManager {
    /// Performs text recognition on an image at the specified file path.
    /// Returns the recognized text separated by newlines, or nil if no text was found.
    static func performOCR(on imagePath: String) -> String? {
        guard FileManager.default.fileExists(atPath: imagePath) else {
            print("OCRManager: Image file does not exist at \(imagePath)")
            return nil
        }
        
        let fileURL = URL(fileURLWithPath: imagePath)
        let requestHandler = VNImageRequestHandler(url: fileURL, options: [:])
        
        var recognizedText = ""
        
        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("OCRManager: Vision request error: \(error)")
                return
            }
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }
            
            var lines: [String] = []
            for observation in observations {
                if let candidate = observation.topCandidates(1).first {
                    lines.append(candidate.string)
                }
            }
            recognizedText = lines.joined(separator: "\n")
        }
        
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        
        do {
            try requestHandler.perform([request])
            let trimmed = recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            print("OCRManager: Failed to perform OCR request: \(error)")
            return nil
        }
    }
}
