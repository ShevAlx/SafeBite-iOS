import UIKit

/// Visual product recognition when there's neither a barcode nor a readable
/// label. Uses Google Cloud Vision Web Detection — it searches the web for
/// visually similar images, which for branded packaging usually gives the
/// exact product name (unlike generic classification like "this is yogurt").
///
/// Talks to the Supabase Edge Function `vision-proxy` instead of Google
/// directly — the Vision API key itself lives only on the server (a Supabase
/// secret), it's not in the app binary and can't be extracted from it.
/// Function deployment is described in `supabase/functions/vision-proxy` and the README.
final class VisualRecognitionService {

    static let shared = VisualRecognitionService()

    private let functionURL = URL(string: "\(Secrets.supabaseProjectURL)/functions/v1/vision-proxy")!
    private let anonKey = Secrets.supabaseAnonKey

    enum RecognitionError: Error {
        case encodingFailed
        case noResult
        case dailyLimitReached
        case network(Error)
    }

    private struct ProxyRequestBody: Encodable {
        let imageBase64: String
    }

    /// Returns the most likely product name from a photo.
    func recognizeProduct(from image: UIImage) async throws -> String {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw RecognitionError.encodingFailed
        }
        let base64 = imageData.base64EncodedString()

        var request = URLRequest(url: functionURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(DeviceIdentifier.current, forHTTPHeaderField: "X-Device-Id")
        request.httpBody = try JSONEncoder().encode(ProxyRequestBody(imageBase64: base64))

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            throw RecognitionError.dailyLimitReached
        }
        let decoded = try JSONDecoder().decode(VisionAPIResponse.self, from: data)

        guard let annotation = decoded.responses.first else {
            throw RecognitionError.noResult
        }

        // Priority — the best guess from Web Detection (usually the exact
        // product name, not just a category).
        if let bestGuess = annotation.webDetection?.bestGuessLabels?.first?.label {
            return bestGuess
        }

        // Fallback — the most confident label from general classification.
        if let topLabel = annotation.labelAnnotations?.first?.description {
            return topLabel
        }

        throw RecognitionError.noResult
    }
}

// MARK: - DTOs for the Google Vision response

private struct VisionAPIResponse: Decodable {
    let responses: [AnnotateImageResponse]
}

private struct AnnotateImageResponse: Decodable {
    let webDetection: WebDetection?
    let labelAnnotations: [LabelAnnotation]?

    enum CodingKeys: String, CodingKey {
        case webDetection
        case labelAnnotations
    }
}

private struct WebDetection: Decodable {
    let bestGuessLabels: [BestGuessLabel]?
}

private struct BestGuessLabel: Decodable {
    let label: String
}

private struct LabelAnnotation: Decodable {
    let description: String
    let score: Double
}
