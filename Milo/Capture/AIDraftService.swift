import UIKit

/// The capture brain: photos/typed meals in → `Product` drafts out.
/// Everything runs on-device (Vision OCR + Apple Foundation Models + the
/// natural-food catalog). The owner always verifies the draft on Confirm —
/// this service never logs anything by itself.
enum FoodAI {

    // MARK: - Packaged food: front + nutrition-label photos → one draft

    struct PackageDraft {
        var product: Product
        /// Fields the pipeline couldn't read — Confirm nudges the owner to fill them.
        var usedAI: Bool
    }

    static func draftPackagedProduct(front: UIImage, back: UIImage?) async -> PackageDraft {
        // 1. OCR both photos on-device (concurrently).
        async let frontTextTask = LabelOCR.recognizeText(in: front)
        async let backTextTask: String = {
            guard let back else { return "" }
            return await LabelOCR.recognizeText(in: back)
        }()
        let (frontText, backText) = await (frontTextTask, backTextTask)

        // 2. Foundation model turns the label text into a structured draft.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleAI.isAvailable {
            if let draft = try? await AppleAI.draftLabel(frontText: frontText, backText: backText) {
                return PackageDraft(product: product(from: draft), usedAI: true)
            }
        }
        #endif

        // 3. No Apple Intelligence → OCR heuristics; the owner fills the gaps.
        let combined = frontText + "\n" + backText
        return PackageDraft(product: LabelOCR.draftProduct(fromOCR: combined), usedAI: false)
    }

    #if canImport(FoundationModels)
    /// Deterministic conversion of the AI's label reading into a Product.
    /// The guaranteed-analysis percentages become grams-per-serving HERE, in
    /// code — the model only reports what the label says.
    @available(iOS 26.0, *)
    private static func product(from draft: AppleAI.LabelDraft) -> Product {
        let grams = Double(max(0, draft.servingGrams))
        func perServing(_ percent: Double) -> Double? {
            guard grams > 0, percent > 0 else { return nil }
            return (percent / 100 * grams * 10).rounded() / 10
        }
        let category = FoodCategory(legacy: draft.category)
        return Product(
            name: draft.name.isEmpty ? "Scanned food" : draft.name,
            brand: draft.brand,
            emoji: category.emoji,
            category: category,
            kcalPerUnit: max(0, draft.kcalPerServing),
            portionBasis: draft.servingBasis.isEmpty ? "serving" : draft.servingBasis,
            ingredients: draft.ingredients,
            verified: false,               // new to the database until confirmed
            isEstimate: draft.isEstimate || draft.kcalPerServing == 0,
            proteinGPerUnit: perServing(draft.proteinPercent),
            fatGPerUnit: perServing(draft.fatPercent),
            fiberGPerUnit: perServing(draft.fiberPercent),
            moistureGPerUnit: perServing(draft.moisturePercent))
    }
    #endif

    // MARK: - Natural meal: the whole batch in ONE pass

    struct MealItemInput: Identifiable, Equatable {
        let id = UUID()
        var name: String = ""
        var portion: String = ""
    }

    /// Estimates a whole meal at once. Catalog foods resolve deterministically;
    /// everything the catalog doesn't know goes to the foundation model in a
    /// single batched call — never one call per item.
    static func estimateMeal(_ inputs: [MealItemInput]) async -> [Product] {
        let cleaned = inputs
            .map { (name: $0.name.trimmingCharacters(in: .whitespaces),
                    portion: $0.portion.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.name.isEmpty }
        guard !cleaned.isEmpty else { return [] }

        // Deterministic first: the bundled USDA-style catalog.
        var resolved = [Int: Product]()
        var unknown = [(index: Int, name: String, portion: String)]()
        for (index, item) in cleaned.enumerated() {
            let portion = item.portion.isEmpty ? "serving" : item.portion
            if let product = NaturalFoodCatalog.estimate(name: item.name, portion: portion) {
                resolved[index] = product
            } else {
                unknown.append((index, item.name, portion))
            }
        }

        // One batched foundation-model call for everything left over.
        #if canImport(FoundationModels)
        if !unknown.isEmpty, #available(iOS 26.0, *), AppleAI.isAvailable {
            let estimates = (try? await AppleAI.estimateMeal(unknown.map { ($0.name, $0.portion) })) ?? []
            for (offset, estimate) in estimates.enumerated() where offset < unknown.count {
                let slot = unknown[offset]
                resolved[slot.index] = Product(
                    name: estimate.name.isEmpty ? slot.name.capitalized : estimate.name.capitalized,
                    brand: "",
                    emoji: estimate.emoji.isEmpty ? "🍽️" : estimate.emoji,
                    category: FoodCategory(legacy: estimate.category),
                    kcalPerUnit: max(0, estimate.kcal),
                    portionBasis: slot.portion,
                    ingredients: estimate.allergen.isEmpty ? [slot.name.lowercased()] : [estimate.allergen],
                    verified: false,
                    isEstimate: true,
                    proteinGPerUnit: max(0, estimate.proteinG),
                    fatGPerUnit: max(0, estimate.fatG),
                    fiberGPerUnit: max(0, estimate.fiberG),
                    moistureGPerUnit: max(0, estimate.moistureG))
            }
        }
        #endif

        // Anything still unresolved becomes a fill-me-in draft (kcal 0 → the
        // Confirm gate makes the owner supply the number, never invents one).
        return cleaned.indices.map { index in
            resolved[index] ?? Product(
                name: cleaned[index].name.capitalized,
                brand: "",
                emoji: "🍽️",
                category: .other,
                kcalPerUnit: 0,
                portionBasis: cleaned[index].portion.isEmpty ? "serving" : cleaned[index].portion,
                ingredients: [cleaned[index].name.lowercased()],
                verified: false,
                isEstimate: true)
        }
    }
}
