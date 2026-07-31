import UIKit
import Vision
import CoreImage

/// On-device text recognition (Apple Vision) for food labels.
/// Free and offline. Two readers live here:
///   • `read(_:)`  — the preferred path. On iOS 26 it uses the document-structure
///     recognizer (`RecognizeDocumentsRequest`) so the guaranteed-analysis table
///     (crude protein / fat / fiber / moisture %) arrives as tidy rows instead of
///     scrambled text, and it perspective-corrects an angled label first. On
///     older systems it degrades to plain OCR.
///   • `recognizeText(in:)` — the plain `VNRecognizeTextRequest` fallback, also
///     used by the no-AI draft.
/// Structured text feeds the Foundation Model a much cleaner prompt; the model
/// still does the language work and Swift still does all the math.
enum LabelOCR {

    /// A label reading, structured where the OS can manage it.
    struct LabelReading {
        /// Full recognized text (document transcript on iOS 26, else joined OCR lines).
        var transcript: String
        /// Detected tables serialized as clean `key | value` rows, or "" if none.
        var tableText: String
        /// True when the iOS 26 document recognizer produced this reading.
        var usedDocumentStructure: Bool

        /// What we hand the language model: transcript plus any structured table
        /// block. The table rows go first so the guaranteed analysis leads.
        var combinedText: String {
            guard !tableText.isEmpty else { return transcript }
            return "GUARANTEED ANALYSIS (structured table rows):\n\(tableText)\n\nFULL LABEL TEXT:\n\(transcript)"
        }
    }

    // MARK: - Preferred reader (structured on iOS 26, plain otherwise)

    /// Reads a label photo: auto-crops/flattens an angled shot, then extracts
    /// structured rows on iOS 26 or plain text on older systems.
    static func read(_ image: UIImage) async -> LabelReading {
        let flattened = flattenedDocument(image) ?? image

        if #available(iOS 26.0, *) {
            if let structured = await readStructured(flattened) {
                return structured
            }
        }
        // Fallback: plain OCR, no table structure.
        let text = await recognizeText(in: flattened)
        return LabelReading(transcript: text, tableText: "", usedDocumentStructure: false)
    }

    /// iOS 26 document-structure recognition. Returns nil on any failure so the
    /// caller can fall back to plain OCR.
    @available(iOS 26.0, *)
    private static func readStructured(_ image: UIImage) async -> LabelReading? {
        guard let cgImage = image.cgImage else { return nil }
        do {
            let request = RecognizeDocumentsRequest()
            let observations = try await request.perform(on: cgImage)
            guard let document = observations.first?.document else { return nil }

            let transcript = document.text.transcript
            let tableText = document.tables
                .map { serialize(table: $0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")

            // If the recognizer read nothing useful, let plain OCR try.
            guard !transcript.isEmpty || !tableText.isEmpty else { return nil }
            return LabelReading(transcript: transcript, tableText: tableText,
                                usedDocumentStructure: true)
        } catch {
            return nil
        }
    }

    /// One detected table → clean rows: `cell | cell | cell` per line. This is
    /// exactly what a guaranteed-analysis grid should look like once destructured.
    @available(iOS 26.0, *)
    private static func serialize(table: DocumentObservation.Container.Table) -> String {
        table.rows.map { row in
            row.map { $0.content.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
               .filter { !$0.isEmpty }
               .joined(separator: " | ")
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    // MARK: - Document detection + perspective correction

    /// Best-effort auto-crop + flatten of a label held at an angle, using Vision
    /// document segmentation and a perspective-correction filter. Returns nil if
    /// no confident document quad is found (the caller then uses the original).
    private static func flattenedDocument(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do { try handler.perform([request]) } catch { return nil }
        guard let quad = request.results?.first, quad.confidence > 0.5 else { return nil }

        let ci = CIImage(cgImage: cgImage)
        let w = ci.extent.width, h = ci.extent.height
        func point(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }

        let filter = CIFilter(name: "CIPerspectiveCorrection")
        filter?.setValue(ci, forKey: kCIInputImageKey)
        filter?.setValue(point(quad.topLeft), forKey: "inputTopLeft")
        filter?.setValue(point(quad.topRight), forKey: "inputTopRight")
        filter?.setValue(point(quad.bottomLeft), forKey: "inputBottomLeft")
        filter?.setValue(point(quad.bottomRight), forKey: "inputBottomRight")
        guard let output = filter?.outputImage else { return nil }

        let context = CIContext()
        guard let corrected = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: corrected)
    }

    // MARK: - Plain OCR (fallback + no-AI draft)

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
