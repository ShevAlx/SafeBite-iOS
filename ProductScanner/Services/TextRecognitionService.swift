import Vision
import UIKit

/// Recognizes the ingredient text straight off the label when there's no
/// barcode or the product isn't in the database — a keyword-based allergen fallback.
final class TextRecognitionService {

    static let shared = TextRecognitionService()

    func recognizeText(in image: UIImage, completion: @escaping (String) -> Void) {
        guard let cgImage = image.cgImage else {
            completion("")
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                completion("")
                return
            }
            let text = observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            completion(text)
        }

        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    /// Looks for allergen keywords in the recognized text.
    /// Used when the product wasn't found in Open Food Facts at all,
    /// and there's no structured allergen data to fall back on.
    func detectAllergens(inText text: String) -> [Allergen] {
        let lowered = text.lowercased()
        return Allergen.allCases.filter { allergen in
            allergen.ocrKeywords.contains { lowered.contains($0) }
        }
    }
}
