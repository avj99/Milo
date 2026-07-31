import Foundation

// Apple Foundation Models (on-device, iOS 26+) — the only AI Milo uses.
// Division of labor, deliberately:
//   • Vision OCR reads the photos (the foundation model is text-only).
//   • The foundation model does LANGUAGE work via guided generation: turning
//     messy label text into a structured draft, normalizing a whole meal of
//     natural foods ("shredded chicken, a handful") into grams + nutrition,
//     and mapping stray ingredient names to canonical allergens — one session,
//     ONE call per meal, never per-item round-trips.
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
    contain recognition errors). The text may include a structured guaranteed-analysis \
    table with clean `key | value` rows — trust those rows for the crude protein, fat, \
    fiber and moisture percentages. Rules: use ONLY what the text supports — never \
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
        \(String(frontText.prefix(1800)))

        NUTRITION / BACK OF PACKAGE (OCR):
        \(String(backText.prefix(2600)))
        """
        return try await session.respond(to: prompt, generating: LabelDraft.self).content
    }

    // MARK: - lookupNutrition tool (grounds fresh-food estimates in the catalog)

    /// A Foundation Models tool the model can call while estimating a meal. It
    /// looks up USDA-style per-100 g values from `NaturalFoodCatalog` so the
    /// model's job is reduced to identifying the food + portion grams — the real
    /// numbers come from the catalog when it hits. Swift, not the model, does the
    /// per-100 g × grams arithmetic downstream (see AIDraftService).
    struct NutritionLookupTool: Tool {
        let name = "lookupNutrition"
        let description = """
        Look up standard per-100 g nutrition (kcal, protein, fat) for a common whole \
        food by name. Call this for each food before answering so your numbers are \
        grounded. Returns a 'no match' note if the food isn't in the reference table, \
        in which case use your own standard USDA values.
        """

        @Generable
        struct Arguments {
            @Guide(description: "A simple canonical food name, e.g. 'chicken breast', 'white rice', 'salmon'")
            var food: String
        }

        func call(arguments: Arguments) async throws -> String {
            guard let food = NaturalFoodCatalog.find(arguments.food) else {
                return "no match for \"\(arguments.food)\" — use your own standard USDA values"
            }
            let allergenNote = food.allergen.map { "; common allergen: \($0)" } ?? ""
            return "\(food.name): \(Int(food.kcalPer100g)) kcal, "
                + "\(food.proteinPer100g) g protein, \(food.fatPer100g) g fat per 100 g"
                + allergenNote
        }
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
        @Guide(description: "Kilocalories for that portion, from lookupNutrition when it matched, else standard USDA-style values")
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
        @Guide(description: "If lookupNutrition returned a match for this food, the exact food name it returned (e.g. 'chicken breast'); otherwise empty string")
        var catalogMatch: String
        @Guide(description: "One short sentence stating the assumption made, e.g. 'assumed a handful is about 30 g'")
        var assumption: String
    }

    @Generable
    struct MealEstimates {
        @Guide(description: "One entry per food item, same order as the input list")
        var items: [FoodEstimate]
    }

    private static let mealInstructions = """
    You estimate nutrition for foods an owner is sharing with their dog. For EACH \
    food, first call the lookupNutrition tool with a simple canonical name to fetch \
    standard per-100 g values; when it matches, base your numbers on those values and \
    put the returned name in catalogMatch. Only fall back to your own standard \
    (USDA-style) values when the tool reports no match. Your main job is identifying \
    the food and the portion in grams — interpret colloquial portions conservatively \
    (a handful ≈ 30 g, a tablespoon ≈ 15 g, a slice of bread ≈ 25 g, one chicken \
    breast ≈ 170 g cooked, one egg ≈ 50 g). Report kcal, protein, fat, fiber and \
    moisture grams for the described portion only — do not total across items; the app \
    does all totalling. State every assumption. Never give feeding advice; numbers only.
    """

    static func estimateMeal(_ entries: [(name: String, portion: String)]) async throws -> [FoodEstimate] {
        guard !entries.isEmpty else { return [] }
        let session = LanguageModelSession(tools: [NutritionLookupTool()],
                                           instructions: mealInstructions)
        let list = entries.enumerated()
            .map { "\($0.offset + 1). \($0.element.name) — portion: \($0.element.portion)" }
            .joined(separator: "\n")
        let prompt = "Estimate each of these foods:\n\(list)"
        return try await session.respond(to: prompt, generating: MealEstimates.self).content.items
    }

    // MARK: - Allergen fallback (leftover ingredients → canonical allergens)

    @Generable
    struct AllergenMapping {
        @Guide(description: "The ingredient exactly as it was given in the input")
        var ingredient: String
        @Guide(description: "Canonical allergen this ingredient clearly derives from: one of chicken, beef, dairy, wheat, egg, soy, fish, lamb, pork, corn — or empty string if none of these clearly apply")
        var allergen: String
    }

    @Generable
    struct AllergenMappings {
        @Guide(description: "One entry per input ingredient, in the same order")
        var items: [AllergenMapping]
    }

    private static let allergenInstructions = """
    You map pet-food ingredient names to a fixed list of canonical dog allergens: \
    chicken, beef, dairy, wheat, egg, soy, fish, lamb, pork, corn. Many allergens \
    hide under processing terms — e.g. 'hydrolyzed poultry by-product' derives from \
    chicken, 'dehydrated poultry protein' from chicken, 'whey' from dairy, 'gluten' \
    from wheat, 'salmon oil' from fish. Only assign an allergen when the ingredient \
    clearly derives from one of the ten; otherwise return an empty string. Do not \
    guess wildly — these are advisory suggestions the owner will review.
    """

    /// Best-effort mapping of ingredients the deterministic synonym map couldn't
    /// place. Returns ingredient(lowercased) → canonical allergen. ONE batched
    /// call. Results are advisory suggestions, not confirmed matches.
    static func mapAllergens(_ ingredients: [String]) async throws -> [String: String] {
        let cleaned = ingredients
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [:] }

        let session = LanguageModelSession(instructions: allergenInstructions)
        let list = cleaned.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let prompt = "Map each ingredient to a canonical allergen if it clearly derives from one:\n\(list)"
        let result = try await session.respond(to: prompt, generating: AllergenMappings.self).content

        var map = [String: String]()
        for item in result.items {
            let canonical = item.allergen.lowercased().trimmingCharacters(in: .whitespaces)
            guard AllergenEngine.canonicalAllergens.contains(canonical) else { continue }
            map[item.ingredient.lowercased().trimmingCharacters(in: .whitespaces)] = canonical
        }
        return map
    }

    // MARK: - Weekly digest (words only — every number comes from a Swift tool)
    //
    // Same "AI estimates, engine calculates" split as the rest of Milo, applied
    // to prose. The digest model gets NO free-floating numbers in its prompt.
    // Instead it is handed two deterministic tools:
    //   • getTrendStat  — retrieves a precomputed statistic (from TrendsModel),
    //     so anything it states is grounded in a real value.
    //   • calculate     — exact arithmetic in Swift, so the model never does
    //     mental math (e.g. "how many points over the 10% treats guideline").
    // The model orchestrates and phrases; Swift owns every figure it prints.

    /// Retrieves precomputed weekly trend statistics by key. Grounds the digest:
    /// the model calls this for each number it wants to mention.
    struct TrendsStatsTool: Tool {
        let name = "getTrendStat"
        let description = """
        Retrieve a precomputed weekly statistic for this dog by key. Call it to \
        ground every number you mention — pass key "list" first to see all keys. \
        Returns "key = value" or a not-found note listing valid keys.
        """
        /// Ordered so "list" reads sensibly; values are preformatted with units.
        let stats: [(key: String, value: String)]

        @Generable
        struct Arguments {
            @Guide(description: "The statistic key to fetch, e.g. 'avgPercentOfTarget', 'avgTreatPercent', 'streak'. Pass 'list' to see every available key.")
            var key: String
        }

        func call(arguments: Arguments) async throws -> String {
            let key = arguments.key.trimmingCharacters(in: .whitespaces)
            if key.caseInsensitiveCompare("list") == .orderedSame {
                return "available keys: " + stats.map(\.key).joined(separator: ", ")
            }
            if let hit = stats.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                return "\(hit.key) = \(hit.value)"
            }
            return "no stat named \"\(key)\". available keys: "
                + stats.map(\.key).joined(separator: ", ")
        }
    }

    /// Exact arithmetic, done in Swift, so the model never computes a number.
    struct TrendsCalculatorTool: Tool {
        let name = "calculate"
        let description = """
        Do exact arithmetic so you never compute in your head. ops: add, subtract, \
        multiply, divide, percentOf (a as a percent of b). Returns the numeric result.
        """

        @Generable
        struct Arguments {
            @Guide(description: "One of exactly: add, subtract, multiply, divide, percentOf")
            var op: String
            @Guide(description: "First operand")
            var a: Double
            @Guide(description: "Second operand")
            var b: Double
        }

        func call(arguments: Arguments) async throws -> String {
            let a = arguments.a, b = arguments.b
            let result: Double
            switch arguments.op.lowercased() {
            case "add":       result = a + b
            case "subtract":  result = a - b
            case "multiply":  result = a * b
            case "divide":    result = b == 0 ? 0 : a / b
            case "percentof": result = b == 0 ? 0 : a / b * 100
            default:
                return "unknown op \"\(arguments.op)\" — use add, subtract, multiply, divide, or percentOf"
            }
            // Trim a trailing .0 so whole numbers read cleanly.
            return result == result.rounded()
                ? String(Int(result.rounded()))
                : String(format: "%.2f", result)
        }
    }

    private static let digestInstructions = """
    You write a short weekly nutrition digest for a dog owner. You have two tools: \
    getTrendStat retrieves precomputed statistics, and calculate does exact \
    arithmetic. NEVER state a number you did not get back from one of those tools — \
    do not estimate, recompute, or invent any figure. Write 2–3 warm, plain-language \
    sentences. Be encouraging; if something sits above a guideline (e.g. treats over \
    10%), mention it gently. This is intake tracking, not veterinary advice — never \
    diagnose or give feeding prescriptions. Return the sentences only.
    """

    /// Two or three grounded sentences summarising the dog's week. Returns nil-safe
    /// text; callers hide the card entirely when the model is unavailable.
    static func weeklyDigest(model: TrendsModel) async throws -> String {
        let session = LanguageModelSession(
            tools: [TrendsStatsTool(stats: model.digestStatMap()), TrendsCalculatorTool()],
            instructions: digestInstructions)
        let prompt = """
        Write this week's nutrition digest for \(model.dog.name). First call \
        getTrendStat with key "list" to see every available statistic, then fetch \
        each number you plan to mention. Use calculate for any arithmetic (for \
        example how many points over or under the 10% treats guideline). Do not \
        print a number you did not receive from a tool.
        """
        return try await session.respond(to: prompt).content
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
