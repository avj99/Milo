import Foundation

/// Reference nutrition for common natural / non-brand foods owners share with
/// dogs. Values are per 100 g, compiled from USDA FoodData Central published
/// figures (raw factual data, not copyrightable). This is the deterministic
/// first line — the on-device AI only estimates foods that miss here, so the
/// everyday cases ("shredded chicken, a handful") never depend on a model.
struct NaturalFood {
    let name: String
    let synonyms: [String]
    let emoji: String
    let kcalPer100g: Double
    let proteinPer100g: Double
    let fatPer100g: Double
    /// Colloquial portions owners actually say, mapped to grams.
    let portions: [(label: String, grams: Double)]
    /// Canonical allergen this food maps to, if any (feeds the allergen engine).
    let allergen: String?
}

enum NaturalFoodCatalog {

    static func find(_ query: String) -> NaturalFood? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return all.first { food in
            food.name == q || food.synonyms.contains(q)
                || q.contains(food.name)
                || food.synonyms.contains(where: { q.contains($0) })
        }
    }

    /// Grams for a colloquial portion phrase ("handful", "1 breast", "half").
    /// Falls back to generic amounts so an unmatched phrase still estimates.
    static func grams(for portion: String, of food: NaturalFood) -> Double {
        let p = portion.lowercased()
        if let hit = food.portions.first(where: { p.contains($0.label) }) {
            let multiplier = leadingNumber(in: p) ?? 1
            return hit.grams * multiplier
        }
        if let generic = genericPortions.first(where: { p.contains($0.label) }) {
            let multiplier = leadingNumber(in: p) ?? 1
            return generic.grams * multiplier
        }
        // "50 g" / "50g"
        if let n = leadingNumber(in: p), p.contains("g") { return n }
        return 30 // a cautious small serving
    }

    private static func leadingNumber(in text: String) -> Double? {
        let digits = text.prefix { $0.isNumber || $0 == "." || $0 == "½" || $0 == "¼" || $0 == "¾" }
        if digits.isEmpty {
            if text.hasPrefix("half") { return 0.5 }
            return nil
        }
        switch digits {
        case "½": return 0.5
        case "¼": return 0.25
        case "¾": return 0.75
        default:  return Double(digits)
        }
    }

    static let genericPortions: [(label: String, grams: Double)] = [
        ("handful", 30), ("cup", 140), ("tbsp", 15), ("tablespoon", 15),
        ("tsp", 5), ("teaspoon", 5), ("slice", 25), ("piece", 20), ("bite", 8),
        ("spoon", 15), ("bowl", 200), ("scoop", 40),
    ]

    // Per-100g values: USDA FoodData Central, cooked where dogs get it cooked.
    static let all: [NaturalFood] = [
        NaturalFood(name: "chicken breast", synonyms: ["chicken", "shredded chicken", "boiled chicken", "grilled chicken"],
                    emoji: "🍗", kcalPer100g: 165, proteinPer100g: 31, fatPer100g: 3.6,
                    portions: [("breast", 170), ("handful", 30), ("cup", 140)], allergen: "chicken"),
        NaturalFood(name: "chicken thigh", synonyms: ["dark meat chicken"],
                    emoji: "🍗", kcalPer100g: 209, proteinPer100g: 26, fatPer100g: 11,
                    portions: [("thigh", 110), ("handful", 30)], allergen: "chicken"),
        NaturalFood(name: "ground beef", synonyms: ["beef", "minced beef", "hamburger meat"],
                    emoji: "🥩", kcalPer100g: 250, proteinPer100g: 26, fatPer100g: 15,
                    portions: [("handful", 30), ("cup", 150), ("patty", 90)], allergen: "beef"),
        NaturalFood(name: "salmon", synonyms: ["cooked salmon", "baked salmon"],
                    emoji: "🐟", kcalPer100g: 206, proteinPer100g: 22, fatPer100g: 12,
                    portions: [("fillet", 150), ("handful", 30)], allergen: "fish"),
        NaturalFood(name: "tuna", synonyms: ["canned tuna"],
                    emoji: "🐟", kcalPer100g: 116, proteinPer100g: 26, fatPer100g: 1,
                    portions: [("can", 120), ("handful", 30)], allergen: "fish"),
        NaturalFood(name: "egg", synonyms: ["boiled egg", "scrambled egg", "eggs"],
                    emoji: "🥚", kcalPer100g: 155, proteinPer100g: 13, fatPer100g: 11,
                    portions: [("egg", 50)], allergen: "egg"),
        NaturalFood(name: "white rice", synonyms: ["rice", "cooked rice", "plain rice"],
                    emoji: "🍚", kcalPer100g: 130, proteinPer100g: 2.7, fatPer100g: 0.3,
                    portions: [("cup", 160), ("scoop", 60)], allergen: nil),
        NaturalFood(name: "sweet potato", synonyms: ["yam", "cooked sweet potato"],
                    emoji: "🍠", kcalPer100g: 90, proteinPer100g: 2, fatPer100g: 0.2,
                    portions: [("cup", 130), ("slice", 30)], allergen: nil),
        NaturalFood(name: "pumpkin", synonyms: ["canned pumpkin", "pumpkin puree"],
                    emoji: "🎃", kcalPer100g: 34, proteinPer100g: 1.1, fatPer100g: 0.1,
                    portions: [("tbsp", 15), ("cup", 245)], allergen: nil),
        NaturalFood(name: "carrot", synonyms: ["carrots", "baby carrot", "baby carrots"],
                    emoji: "🥕", kcalPer100g: 41, proteinPer100g: 0.9, fatPer100g: 0.2,
                    portions: [("carrot", 60), ("baby carrot", 10), ("handful", 40)], allergen: nil),
        NaturalFood(name: "apple", synonyms: ["apple slices"],
                    emoji: "🍎", kcalPer100g: 52, proteinPer100g: 0.3, fatPer100g: 0.2,
                    portions: [("apple", 180), ("slice", 20)], allergen: nil),
        NaturalFood(name: "banana", synonyms: ["bananas"],
                    emoji: "🍌", kcalPer100g: 89, proteinPer100g: 1.1, fatPer100g: 0.3,
                    portions: [("banana", 120), ("slice", 10)], allergen: nil),
        NaturalFood(name: "blueberries", synonyms: ["blueberry"],
                    emoji: "🫐", kcalPer100g: 57, proteinPer100g: 0.7, fatPer100g: 0.3,
                    portions: [("handful", 35), ("cup", 150)], allergen: nil),
        NaturalFood(name: "watermelon", synonyms: [],
                    emoji: "🍉", kcalPer100g: 30, proteinPer100g: 0.6, fatPer100g: 0.2,
                    portions: [("cube", 20), ("slice", 280), ("cup", 150)], allergen: nil),
        NaturalFood(name: "green beans", synonyms: ["green bean"],
                    emoji: "🫛", kcalPer100g: 31, proteinPer100g: 1.8, fatPer100g: 0.2,
                    portions: [("handful", 30), ("cup", 100)], allergen: nil),
        NaturalFood(name: "peanut butter", synonyms: ["pb"],
                    emoji: "🥜", kcalPer100g: 588, proteinPer100g: 25, fatPer100g: 50,
                    portions: [("tsp", 5), ("tbsp", 16), ("spoon", 16), ("lick", 5)], allergen: nil),
        NaturalFood(name: "cheese", synonyms: ["cheddar", "cheese cube"],
                    emoji: "🧀", kcalPer100g: 403, proteinPer100g: 25, fatPer100g: 33,
                    portions: [("cube", 10), ("slice", 20), ("handful", 30)], allergen: "dairy"),
        NaturalFood(name: "plain yogurt", synonyms: ["yogurt", "greek yogurt"],
                    emoji: "🥛", kcalPer100g: 61, proteinPer100g: 3.5, fatPer100g: 3.3,
                    portions: [("tbsp", 15), ("spoon", 15), ("cup", 245)], allergen: "dairy"),
        NaturalFood(name: "bread", synonyms: ["toast", "white bread"],
                    emoji: "🍞", kcalPer100g: 265, proteinPer100g: 9, fatPer100g: 3.2,
                    portions: [("slice", 25), ("crust", 10), ("piece", 15)], allergen: "wheat"),
        NaturalFood(name: "turkey", synonyms: ["turkey breast", "ground turkey"],
                    emoji: "🦃", kcalPer100g: 147, proteinPer100g: 25, fatPer100g: 5,
                    portions: [("handful", 30), ("slice", 28), ("cup", 140)], allergen: nil),
        NaturalFood(name: "pork", synonyms: ["pork loin", "pork chop"],
                    emoji: "🥩", kcalPer100g: 231, proteinPer100g: 27, fatPer100g: 13,
                    portions: [("handful", 30), ("chop", 130)], allergen: "pork"),
        NaturalFood(name: "cucumber", synonyms: ["cucumbers"],
                    emoji: "🥒", kcalPer100g: 15, proteinPer100g: 0.7, fatPer100g: 0.1,
                    portions: [("slice", 7), ("handful", 40)], allergen: nil),
        NaturalFood(name: "broccoli", synonyms: [],
                    emoji: "🥦", kcalPer100g: 35, proteinPer100g: 2.4, fatPer100g: 0.4,
                    portions: [("floret", 15), ("cup", 90)], allergen: nil),
        NaturalFood(name: "oatmeal", synonyms: ["oats", "cooked oatmeal"],
                    emoji: "🥣", kcalPer100g: 71, proteinPer100g: 2.5, fatPer100g: 1.5,
                    portions: [("spoon", 20), ("cup", 234)], allergen: nil),
        NaturalFood(name: "cottage cheese", synonyms: [],
                    emoji: "🥛", kcalPer100g: 98, proteinPer100g: 11, fatPer100g: 4.3,
                    portions: [("tbsp", 15), ("cup", 225)], allergen: "dairy"),
        NaturalFood(name: "sardines", synonyms: ["sardine"],
                    emoji: "🐟", kcalPer100g: 208, proteinPer100g: 25, fatPer100g: 11,
                    portions: [("sardine", 12), ("can", 90)], allergen: "fish"),
        NaturalFood(name: "liver", synonyms: ["beef liver", "chicken liver"],
                    emoji: "🥩", kcalPer100g: 175, proteinPer100g: 26, fatPer100g: 5,
                    portions: [("piece", 20), ("handful", 30)], allergen: nil),
        NaturalFood(name: "strawberries", synonyms: ["strawberry"],
                    emoji: "🍓", kcalPer100g: 32, proteinPer100g: 0.7, fatPer100g: 0.3,
                    portions: [("strawberry", 12), ("handful", 40)], allergen: nil),
    ]

    /// Category per catalog food — meat/fish/veg/fruit/dairy/grain taxonomy.
    static func category(of food: NaturalFood) -> FoodCategory {
        switch food.name {
        case "chicken breast", "chicken thigh", "ground beef", "turkey", "pork", "liver":
            return .meat
        case "salmon", "tuna", "sardines":
            return .fish
        case "carrot", "green beans", "pumpkin", "broccoli", "cucumber", "sweet potato":
            return .vegetable
        case "apple", "banana", "blueberries", "watermelon", "strawberries":
            return .fruit
        case "egg", "cheese", "plain yogurt", "cottage cheese":
            return .dairy
        case "white rice", "bread", "oatmeal":
            return .grain
        default:
            return .other
        }
    }

    /// Deterministic estimate for a natural food, if we know it.
    static func estimate(name: String, portion: String) -> Product? {
        guard let food = find(name) else { return nil }
        return product(for: food, grams: grams(for: portion, of: food), portion: portion)
    }

    /// Builds a Product from a known catalog food + a resolved gram weight. This
    /// is where the per-100 g × grams arithmetic lives, so both the deterministic
    /// path and the AI's `lookupNutrition`-grounded path get identical, Swift-
    /// computed numbers (the model never multiplies).
    static func product(for food: NaturalFood, grams: Double, portion: String) -> Product {
        let factor = grams / 100
        return Product(
            name: food.name.capitalized,
            brand: "",
            emoji: food.emoji,
            category: category(of: food),
            kcalPerUnit: max(1, Int((food.kcalPer100g * factor).rounded())),
            portionBasis: portion.trimmingCharacters(in: .whitespaces).isEmpty ? "serving" : portion,
            ingredients: [food.allergen ?? food.name],
            verified: true,          // reference-table values, not crowdsourced
            isEstimate: true,        // portion size is still a human guess
            proteinGPerUnit: (food.proteinPer100g * factor * 10).rounded() / 10,
            fatGPerUnit: (food.fatPer100g * factor * 10).rounded() / 10)
    }
}
