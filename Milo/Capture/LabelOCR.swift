import UIKit
import Vision

/// On-device text recognition (Apple Vision) for food labels.
/// Free and offline. Used two ways: its text rides along as a hint to the
/// cloud AI draft, and it powers a degraded-but-useful draft when the AI
/// isn't available (signed out, no key configured, offline).
enum LabelOCR {

    static func recognizeText(in image: UIImage) async -> String {
        guard let cgImage = image.cgImage else { return "" }
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage)
                do { try handler.perform([request]) }
                catch { continuation.resume(returning: "") }
            }
        }
    }

    /// Best-effort draft straight from OCR text — the no-AI fallback.
    /// Pulls a kcal figure and an ingredient list if the label shows them;
    /// everything is marked unverified + estimate so Confirm makes that clear.
    static func draftProduct(fromOCR text: String) -> Product {
        Product(
            name: guessName(from: text) ?? "Scanned food",
            brand: "",
            emoji: "🍽️",
            category: .treat,
            kcalPerUnit: parseKcal(from: text) ?? 0,
            portionBasis: "serving",
            ingredients: parseIngredients(from: text),
            verified: false,
            isEstimate: true)
    }

    /// First reasonably wordy line — labels usually lead with the product name.
    private static func guessName(from text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count >= 4 && $0.rangeOfCharacter(from: .letters) != nil }
            .map { String($0.prefix(40)) }
    }

    /// Matches "320 kcal", "kcal/cup 342", "3,450 kcal ME/kg" etc. and prefers
    /// per-serving-scale numbers over per-kg ones.
    private static func parseKcal(from text: String) -> Int? {
        let pattern = #"(\d{1,3}(?:[.,]\d{3})*|\d+)\s*k?cal"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let values = regex.matches(in: text, range: range).compactMap { match -> Int? in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            return Int(text[r].replacingOccurrences(of: ",", with: "")
                              .replacingOccurrences(of: ".", with: ""))
        }
        // Per-kg values (thousands) aren't a portion; prefer the smallest plausible one.
        return values.filter { (5...1500).contains($0) }.min() ?? values.min()
    }

    private static func parseIngredients(from text: String) -> [String] {
        guard let range = text.range(of: "ingredients", options: .caseInsensitive) else { return [] }
        let after = text[range.upperBound...]
            .drop { $0 == ":" || $0 == " " }
        // The list conventionally ends at the first period.
        let list = after.split(separator: ".").first.map(String.init) ?? String(after)
        return list
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty && $0.count < 40 }
            .prefix(25)
            .map { String($0) }
    }
}
