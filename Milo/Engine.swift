import Foundation

// MARK: - Calorie engine
//
// Daily targets come from standard veterinary formulas (Merck Veterinary Manual):
//   RER = 70 × (ideal kg)^0.75              — exponential, valid at any weight
//   RER = (30 × ideal kg) + 70              — linear, valid ~2–45 kg
//   MER = RER × life-stage/activity factor  — the daily target
//
// We use IDEAL weight, treat the result as an estimate (individual dogs vary by
// 20%+), and never present it as a medical prescription.

enum CalorieEngine {

    /// Resting energy requirement, kcal/day.
    static func rer(idealWeightKg kg: Double) -> Double {
        // Prefer the linear form in its valid band; fall back to exponential.
        if kg >= 2 && kg <= 45 {
            return 30 * kg + 70
        }
        return 70 * pow(kg, 0.75)
    }

    /// Maintenance energy requirement (the daily target), rounded to nearest 10.
    static func dailyTarget(for dog: Dog) -> Int {
        var factor = dog.lifeStage.factor
        // Body condition nudges the factor: heavier dogs trend toward the
        // weight-management end. This is a gentle default, not a vet's plan.
        switch dog.bodyCondition {
        case .obese:       factor = min(factor, 1.2)
        case .overweight:  factor = min(factor, 1.4)
        default:           break
        }
        let mer = rer(idealWeightKg: dog.idealWeightKg) * factor
        return Int((mer / 10).rounded()) * 10
    }
}

// MARK: - Allergen engine
//
// Mechanically this is ingredient matching done well. The hard part is the
// hidden-name problem: chicken hides as "poultry fat", "chicken meal",
// "hydrolyzed protein", and more. A synonym map from surface terms to canonical
// allergens is what makes the feature actually work. Framing stays non-medical:
// we surface "contains an ingredient your dog reacts to — check with your vet",
// we never diagnose.

enum AllergenEngine {

    /// Surface ingredient term → canonical allergen. In the real app this is
    /// backed by the AI normalization step; here it is a representative seed map.
    static let synonymMap: [String: String] = [
        // chicken
        "chicken": "chicken", "chicken breast": "chicken", "chicken meal": "chicken",
        "chicken fat": "chicken", "poultry": "chicken", "poultry fat": "chicken",
        "poultry meal": "chicken", "dehydrated chicken": "chicken",
        // beef
        "beef": "beef", "beef meal": "beef", "beef tallow": "beef", "bison": "beef",
        // dairy
        "milk": "dairy", "cheese": "dairy", "whey": "dairy", "yogurt": "dairy",
        "casein": "dairy", "lactose": "dairy",
        // wheat / grain
        "wheat": "wheat", "wheat gluten": "wheat", "wheat flour": "wheat",
        "gluten": "wheat",
        // egg
        "egg": "egg", "dried egg": "egg", "egg product": "egg",
        // soy
        "soy": "soy", "soybean": "soy", "soybean meal": "soy", "soy protein": "soy",
        // fish
        "fish": "fish", "salmon": "fish", "fish meal": "fish", "fish oil": "fish",
        "tuna": "fish", "whitefish": "fish",
        // lamb, pork, corn
        "lamb": "lamb", "lamb meal": "lamb",
        "pork": "pork", "pork meal": "pork", "bacon": "pork", "ham": "pork",
        "corn": "corn", "corn gluten": "corn", "cornmeal": "corn",
    ]

    /// Normalize an ingredient list to canonical allergen names.
    static func normalize(_ ingredients: [String]) -> Set<String> {
        var canon = Set<String>()
        for raw in ingredients {
            let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
            if let hit = synonymMap[key] {
                canon.insert(hit)
                continue
            }
            // Fall back to substring containment so "chicken breast fillet" still hits.
            for (surface, canonical) in synonymMap where key.contains(surface) {
                canon.insert(canonical)
            }
        }
        return canon
    }

    /// The allergens in `product` that this specific `dog` reacts to.
    static func flags(for dog: Dog, product: Product) -> [Allergen] {
        let present = normalize(product.ingredients)
        return dog.allergens.filter { present.contains($0.canonical.lowercased()) }
    }

    /// Does this product trip any *hard* allergy for the dog?
    static func hasHardFlag(for dog: Dog, product: Product) -> Bool {
        flags(for: dog, product: product).contains { $0.severity == .hard }
    }
}
