import Foundation

// Apple Foundation Models (on-device, iOS 26+) — the only AI Milo uses.
// Division of labor, deliberately:
//   • Vision OCR reads the photos (the foundation model is text-only).
//   • The foundation model does LANGUAGE work via guided generation: turning
//     messy label text into a structured draft, and normalizing a whole meal
//     of natural foods ("shredded chicken, a handful") into grams + nutrition
//     — one session, ONE call per meal, never per-item round-trips.
//   • The deterministic engines do all MATH (portions, totals, ring targets).
// On devices without Apple Intelligence everything degrades to the catalog +
// OCR heuristics + manual entry; no cloud calls anywhere.
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, *)
enum AppleAI {

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    // MARK: - Package label → structured draft

    @Generable
    struct LabelDraft {
        @Guide(description: "Product name as printed on the front, e.g. 'Grain-Free Salmon Recipe'")
        var name: String
        @Guide(description: "Brand name if printed, else empty string")
        var brand: String
        @Guide(description: "One of exactly: kibble, wet, treat, meat, fish, vegetable, fruit, dairy, grain, supplement, other. kibble = dry dog food, wet = canned dog food, treat = dog treat/chew")
        var category: String
        @Guide(description: "The label's serving unit, e.g. 'cup', '2 treats', 'can'. If only per-kg energy is given, use 'cup' for kibble")
        var servingBasis: String
        @Guide(description: "Kilocalories (kcal ME) per one servingBasis. Convert from kcal/kg only if the serving weight is stated. 0 if not determinable")
        var kcalPerServing: Int
        @Guide(description: "Weight of one servingBasis in grams if stated or reliably inferable from the label, else 0")
        var servingGrams: Int
        @Guide(description: "Crude protein percent from the guaranteed analysis, else 0")
        var proteinPercent: Double
        @Guide(description: "Crude fat percent from the guaranteed analysis, else 0")
        var fatPercent: Double
        @Guide(description: "Crude fiber percent from the guaranteed analysis, else 0")
        var fiberPercent: Double
        @Guide(description: "Moisture percent from the guaranteed analysis, else 0")
        var moisturePercent: Double
        @Guide(description: "Ingredient list from the label, lowercase, in printed order. Empty if not readable")
        var ingredients: [String]
        @Guide(description: "true if any number was estimated rather than read off the label")
        var isEstimate: Bool
    }

    private static let labelInstructions = """
    You extract structured data from pet-food label text captured by OCR (it may \
    contain recognition errors). Rules: use ONLY what the text supports — never \
    invent brands or numbers. Dog food energy is stated as kcal ME per kg, per cup, \
    or per treat; report kcal for ONE serving of the servingBasis you choose. The \
    guaranteed analysis lists crude protein, crude fat, crude fiber and moisture as \
    percentages — report those percentages exactly as printed. If a value is absent, \
    use 0 or an empty string, and set isEstimate=true for anything you had to infer.
    """

    static func draftLabel(frontText: String, backText: String) async throws -> LabelDraft {
        let session = LanguageModelSession(instructions: labelInstructions)
        let prompt = """
        FRONT OF PACKAGE (OCR):
        \(String(frontText.prefix(1500)))

        NUTRITION / BACK OF PACKAGE (OCR):
        \(String(backText.prefix(2200)))
        """
        return try await session.respond(to: prompt, generating: LabelDraft.self).content
    }

    // MARK: - Natural meal → batch nutrition estimate (ONE call per meal)

    @Generable
    struct FoodEstimate {
        @Guide(description: "The food, cleaned up, e.g. 'shredded chicken breast'")
        var name: String
        @Guide(description: "Single food emoji")
        var emoji: String
        @Guide(description: "Assumed weight of the described portion in grams")
        var grams: Int
        @Guide(description: "Kilocalories for that portion, from standard USDA-style values for the cooked food")
        var kcal: Int
        @Guide(description: "Grams of protein for that portion")
        var proteinG: Double
        @Guide(description: "Grams of fat for that portion")
        var fatG: Double
        @Guide(description: "Grams of dietary fiber for that portion")
        var fiberG: Double
        @Guide(description: "Grams of water/moisture in that portion")
        var moistureG: Double
        @Guide(description: "One of exactly: meat, fish, vegetable, fruit, dairy, grain, treat, supplement, other")
        var category: String
        @Guide(description: "Canonical allergen if this food is a common dog allergen: one of chicken, beef, dairy, wheat, egg, soy, fish, lamb, pork, corn — else empty string")
        var allergen: String
        @Guide(description: "One short sentence stating the assumption made, e.g. 'assumed a handful is about 30 g'")
        var assumption: String
    }

    @Generable
    struct MealEstimates {
        @Guide(description: "One entry per food item, same order as the input list")
        var items: [FoodEstimate]
    }

    private static let mealInstructions = """
    You estimate nutrition for foods an owner is sharing with their dog, using \
    standard published (USDA-style) values for the cooked food. Interpret \
    colloquial portions conservatively (a handful ≈ 30 g, a tablespoon ≈ 15 g, a \
    slice of bread ≈ 25 g, one chicken breast ≈ 170 g cooked, one egg ≈ 50 g). \
    Estimate kcal, protein, fat, fiber and moisture grams for the described \
    portion only — do not total across items; the app does all totalling. State \
    every assumption. Never give feeding advice; numbers only.
    """

    static func estimateMeal(_ entries: [(name: String, portion: String)]) async throws -> [FoodEstimate] {
        guard !entries.isEmpty else { return [] }
        let session = LanguageModelSession(instructions: mealInstructions)
        let list = entries.enumerated()
            .map { "\($0.offset + 1). \($0.element.name) — portion: \($0.element.portion)" }
            .joined(separator: "\n")
        let prompt = "Estimate each of these foods:\n\(list)"
        return try await session.respond(to: prompt, generating: MealEstimates.self).content.items
    }
}
#endif
