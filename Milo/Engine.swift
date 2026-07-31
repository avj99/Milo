import Foundation

// MARK: - Calorie engine
//
// Peer-reviewed veterinary formulas (NRC 2006 · FEDIAF · Merck Veterinary Manual):
//
//   RER  = 70 × (kg)^0.75                          resting energy, any weight
//   Adult MER = RER(ideal weight) × life-stage factor
//   Puppy MER = 130 × (kg)^0.75 × 3.2 × (e^(−0.87·p) − 0.1)      NRC growth eq,
//               p = current weight ÷ expected adult weight
//
// The adult path uses IDEAL weight (refined by body-condition score, which is a
// more reliable signal than breed). The puppy path uses CURRENT weight and the
// breed's expected adult weight, because a growing dog must NOT be fed on an
// adult formula. Everything is presented as an estimate, never a prescription.

/// Result of a calorie calculation, with the method used and safety caveats to
/// surface in the UI so we never lead an owner down the wrong path.
struct CalorieResult {
    enum Method { case adult, puppyGrowth }
    var kcal: Int
    var method: Method
    var idealWeightKg: Double
    var caveats: [String]
}

enum CalorieEngine {

    /// Resting energy requirement (kcal/day). The exponential form is valid at
    /// any weight, so we use it consistently (the linear form is only an
    /// approximation for 2–45 kg).
    static func rer(kg: Double) -> Double { 70 * pow(max(0.1, kg), 0.75) }

    /// Adult life-stage/activity factor, nudged by body condition toward weight
    /// management for heavier dogs.
    static func adultFactor(for dog: Dog) -> Double {
        var f = dog.lifeStage.factor
        switch dog.bodyCondition {
        case .obese:      f = min(f, 1.2)
        case .overweight: f = min(f, 1.4)
        default:          break
        }
        return f
    }

    /// The full result — decides puppy vs adult from age + the breed's maturity.
    static func result(for dog: Dog) -> CalorieResult {
        let breed = BreedCatalog.find(dog.breed)
        let maturity = breed?.size.maturityMonths ?? 12

        if dog.ageMonths < maturity {
            // Puppy growth curve (NRC 2006). Needs an expected adult weight;
            // the breed midpoint is the best estimate, else a gentle guess.
            let adult = max(dog.weightKg,
                            breed?.midKg ?? (dog.idealWeightKg > 0 ? dog.idealWeightKg : dog.weightKg * 2))
            let p = min(1, max(0.05, dog.weightKg / adult))
            let mer = 130 * pow(max(0.1, dog.weightKg), 0.75) * 3.2 * (exp(-0.87 * p) - 0.1)
            var caveats = ["Growing puppies' needs change fast — recheck every few weeks and confirm portions with your vet."]
            if breed == nil {
                caveats.append("Add a breed for a more accurate growth estimate.")
            }
            return CalorieResult(kcal: round10(mer), method: .puppyGrowth,
                                 idealWeightKg: adult, caveats: caveats)
        }

        // Adult maintenance, using ideal (target) weight.
        let ideal = dog.idealWeightKg > 0 ? dog.idealWeightKg : (breed?.midKg ?? dog.weightKg)
        let kcal = round10(rer(kg: ideal) * adultFactor(for: dog))
        var caveats = ["An estimate to start from — individual dogs vary 20%+. Fine-tune with your vet."]
        if dog.bodyCondition == .overweight || dog.bodyCondition == .obese {
            caveats.append("Body condition suggests overweight — this targets the ideal weight. Aim for gradual loss with your vet, not a crash diet.")
        } else if dog.bodyCondition == .veryLean {
            caveats.append("Body condition looks lean — check with your vet whether to feed toward a little more.")
        }
        return CalorieResult(kcal: kcal, method: .adult, idealWeightKg: ideal, caveats: caveats)
    }

    static func dailyTarget(for dog: Dog) -> Int { result(for: dog).kcal }

    static func round10(_ x: Double) -> Int { max(0, Int((x / 10).rounded()) * 10) }

    // MARK: Protein & fat targets
    //
    // AAFCO Dog Food Nutrient Profiles express minimums per 1000 kcal ME:
    //   adult maintenance — crude protein 45.0 g, crude fat 13.8 g
    //   growth/reproduction — crude protein 56.3 g, crude fat 21.3 g
    // Scaling those by the dog's daily calorie target gives per-day gram
    // minimums that stay consistent with the calorie engine. Deterministic on
    // purpose: the AI estimates food facts, this computes the rings.

    /// Minimum grams of protein per day for this dog (AAFCO, scaled to target).
    static func proteinTargetG(for dog: Dog) -> Int {
        let perMcal = dog.isGrowing ? 56.3 : 45.0
        return Int((Double(dog.dailyTarget) / 1000 * perMcal).rounded())
    }

    /// Minimum grams of fat per day for this dog (AAFCO, scaled to target).
    static func fatTargetG(for dog: Dog) -> Int {
        let perMcal = dog.isGrowing ? 21.3 : 13.8
        return Int((Double(dog.dailyTarget) / 1000 * perMcal).rounded())
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
