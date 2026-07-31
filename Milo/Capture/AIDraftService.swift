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
        // 1. Read both photos on-device (concurrently). On iOS 26 this uses
        //    document-structure recognition so the guaranteed-analysis table
        //    arrives as clean rows; older systems get plain OCR.
        async let frontReadingTask = LabelOCR.read(front)
        async let backReadingTask: LabelOCR.LabelReading? = {
            guard let back else { return nil }
            return await LabelOCR.read(back)
        }()
        let (frontReading, backReading) = await (frontReadingTask, backReadingTask)
        let frontText = frontReading.combinedText
        let backText = backReading?.combinedText ?? ""

        // 2. Foundation model turns the label text into a structured draft, then
        //    an allergen-mapping pass rescues ingredients the synonym map missed.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleAI.isAvailable {
            if let draft = try? await AppleAI.draftLabel(frontText: frontText, backText: backText) {
                let base = product(from: draft)
                let enriched = await withAISuggestedAllergens(base)
                return PackageDraft(product: enriched, usedAI: true)
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

    /// Allergen fallback: the deterministic synonym map runs first; only the
    /// ingredients it couldn't place (e.g. "hydrolyzed poultry by-product") go to
    /// the on-device model, in ONE batched call. Any canonical allergens it finds
    /// are appended as advisory suggestions so the per-dog allergy check surfaces
    /// them — the owner still reviews and can edit them out on Confirm.
    @available(iOS 26.0, *)
    private static func withAISuggestedAllergens(_ product: Product) async -> Product {
        let leftovers = AllergenEngine.unmatchedIngredients(product.ingredients)
        guard !leftovers.isEmpty,
              let map = try? await AppleAI.mapAllergens(leftovers), !map.isEmpty else {
            return product
        }
        // Only add allergens the map didn't already imply, so nothing duplicates.
        let alreadyKnown = AllergenEngine.normalize(product.ingredients)
        let suggested = Set(map.values).subtracting(alreadyKnown)
        guard !suggested.isEmpty else { return product }
        var updated = product
        updated.ingredients.append(contentsOf: suggested.sorted())
        return updated
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
                resolved[slot.index] = product(from: estimate, slot: slot)
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

    #if canImport(FoundationModels)
    /// Turns one AI food estimate into a Product. When the model grounded the
    /// food via `lookupNutrition` (catalogMatch set), Swift RECOMPUTES the numbers
    /// from the catalog's per-100 g values × the model's gram estimate — the
    /// model's own kcal/protein/fat are discarded so the math stays deterministic.
    /// Otherwise the model's USDA-style estimate is used as-is.
    @available(iOS 26.0, *)
    private static func product(from estimate: AppleAI.FoodEstimate,
                                slot: (index: Int, name: String, portion: String)) -> Product {
        // Catalog-grounded path: numbers come from the reference table.
        let matchKey = estimate.catalogMatch.trimmingCharacters(in: .whitespaces)
        if !matchKey.isEmpty, let food = NaturalFoodCatalog.find(matchKey) {
            let grams = estimate.grams > 0
                ? Double(estimate.grams)
                : NaturalFoodCatalog.grams(for: slot.portion, of: food)
            return NaturalFoodCatalog.product(for: food, grams: grams, portion: slot.portion)
        }

        // Model-estimate path (no catalog hit): use the model's own values.
        return Product(
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
    #endif
}

// MARK: - Plausibility guardrails (pure rules, no AI)
//
// After extraction, sanity-check the numbers against how real dog food behaves.
// Nothing here is auto-corrected or silently dropped — implausible fields are
// surfaced on Confirm in an orange "double-check" state so the owner decides.
// All math available from a Product; no serving-weight field, so weight-based
// checks estimate the serving mass from the calories + food type.

enum Plausibility {

    /// Which Confirm rows to flag, each with a plain-language reason. Maps 1:1 to
    /// the "Calories" and "Nutrition" rows the Confirm card shows.
    struct Result: Equatable {
        var calories: String?
        var nutrition: String?
        var isClean: Bool { calories == nil && nutrition == nil }
        var isFlagged: Bool { !isClean }
    }

    /// Sanity-check one product's extracted numbers. `combined` skips the
    /// weight-sum check for a synthesized meal total (which isn't one food).
    static func check(_ p: Product, combined: Bool = false) -> Result {
        var result = Result()
        let kcal = Double(p.kcalPerUnit)
        let basis = p.portionBasis.lowercased()

        // --- Calorie sanity, by category + portion basis ---
        if kcal > 0 {
            if basis.contains("kg") {
                if p.category == .kibble, !(2800...5200).contains(kcal) {
                    result.calories = "Dry food is usually ~3,000–4,500 kcal/kg — this looks off."
                } else if p.category == .wet, kcal > 2200 {
                    result.calories = "Wet food is usually well under 2,000 kcal/kg — this looks off."
                }
            } else if p.category == .treat {
                if kcal > 160 {
                    result.calories = "A single treat is usually 1–150 kcal — this looks high."
                }
            } else if basis.contains("cup"), p.category.isMainMeal {
                if !(180...620).contains(kcal) {
                    result.calories = "A cup of dry food is usually ~250–550 kcal — double-check."
                }
            } else if kcal > 1500 {
                result.calories = "That's a lot of calories for one portion — double-check."
            }
        }

        // --- Guaranteed-analysis sanity ---
        let ga = [p.proteinGPerUnit, p.fatGPerUnit, p.fiberGPerUnit, p.moistureGPerUnit]
            .compactMap { $0 }.reduce(0, +)

        // The nutrient grams can't outweigh the food itself. Estimate the serving
        // mass from calories + typical energy density, then require the analysis
        // to fit inside it (with slack). Catches percent→grams misreads.
        if !combined, ga > 0, kcal > 0 {
            let estServingG = kcal / energyDensity(for: p.category)
            if ga > estServingG * 1.3 {
                result.nutrition = "These nutrition amounts add up to more than the food could weigh — double-check."
            }
        }

        // Macro energy can't exceed the stated calories (protein 4 / fat 9 kcal/g).
        if result.nutrition == nil, kcal > 0,
           let pr = p.proteinGPerUnit, let ft = p.fatGPerUnit,
           pr * 4 + ft * 9 > kcal * 1.35 {
            result.nutrition = "Protein/fat look high for the stated calories — double-check."
        }

        return result
    }

    /// Rough kcal-per-gram by food type, for estimating serving mass from calories.
    private static func energyDensity(for category: FoodCategory) -> Double {
        switch category {
        case .kibble, .treat, .grain, .supplement: return 3.5
        case .wet:                                  return 1.0
        case .meat, .fish, .dairy:                  return 1.8
        case .vegetable, .fruit:                    return 0.5
        case .other:                                return 2.0
        }
    }
}
