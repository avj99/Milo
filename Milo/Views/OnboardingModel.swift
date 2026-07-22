import SwiftUI

/// Drives the 12-step first-run onboarding, ported from the Claude Design file
/// "Milo Onboarding.dc.html". Holds every field the flow collects and computes
/// the daily-target reveal with the design's own factor model, then maps the
/// answers onto the app's `Dog` model.
@MainActor
final class OnboardingModel: ObservableObject {
    enum Mode { case new, join }

    @Published var step: Int = 0
    @Published var mode: Mode = .new

    // Household
    @Published var householdName = ""
    @Published var inviteCode = ""

    // Dog
    @Published var dogName = ""
    @Published var dogPhoto = false
    @Published var breed: String? = nil
    @Published var breedSize = ""
    @Published var ageMonths = 24
    @Published var sexFemale = true
    @Published var neutered = true
    @Published var weightKg: Double = 28
    @Published var unitKg = true
    @Published var bcs = 2          // 0…4 (default: Ideal)
    @Published var activity = 1     // 0…2
    @Published var allergens: [String] = []

    // Search fields
    @Published var breedQuery = ""
    @Published var allergenQuery = ""

    // MARK: Reference data (from the design)

    let breeds: [(name: String, size: String)] = [
        ("Labrador Retriever", "Large · ~30 kg"), ("Golden Retriever", "Large · ~29 kg"),
        ("French Bulldog", "Small · ~12 kg"), ("German Shepherd", "Large · ~34 kg"),
        ("Poodle (Standard)", "Medium · ~22 kg"), ("Beagle", "Small · ~11 kg"),
        ("Dachshund", "Small · ~8 kg"), ("Border Collie", "Medium · ~18 kg"),
        ("Shih Tzu", "Small · ~6 kg"), ("Boxer", "Large · ~30 kg"),
        ("Australian Shepherd", "Medium · ~24 kg"), ("Cavalier K.C. Spaniel", "Small · ~8 kg"),
        ("Chihuahua", "Toy · ~3 kg"), ("Great Dane", "Giant · ~60 kg"), ("Corgi", "Small · ~13 kg"),
    ]

    let allergenOptions = ["Chicken", "Beef", "Dairy", "Egg", "Wheat / grain", "Lamb",
                           "Fish", "Soy", "Pork", "Turkey", "Corn", "Peas"]

    struct BCSInfo { let label, tag, desc: String; let rx, ry, headX: CGFloat }
    let bcsInfo: [BCSInfo] = [
        .init(label: "Too thin", tag: "too thin", desc: "Ribs, spine and hip bones stand out with no fat. A tucked, bony look — worth building back up.", rx: 34, ry: 11, headX: 20),
        .init(label: "Lean", tag: "lean", desc: "Ribs easily felt with little fat. Slightly light — fine for very active dogs.", rx: 40, ry: 15, headX: 20),
        .init(label: "Ideal", tag: "ideal", desc: "Ribs easily felt, a visible waist from above and a tucked belly from the side. This is the sweet spot.", rx: 45, ry: 19, headX: 20),
        .init(label: "Overweight", tag: "overweight", desc: "Ribs hard to feel under fat, waist barely visible. A little to lose over time.", rx: 50, ry: 24, headX: 19),
        .init(label: "Heavy", tag: "heavy", desc: "Ribs difficult to feel, no waist, fat deposits over the back. Worth a gentle plan with your vet.", rx: 55, ry: 28, headX: 18),
    ]

    struct ActInfo { let label, desc: String; let bars: Int }
    let acts: [ActInfo] = [
        .init(label: "Couch companion", desc: "Short walks, lots of naps", bars: 1),
        .init(label: "Moderately active", desc: "Daily walks and regular play", bars: 2),
        .init(label: "Very active / working", desc: "Runs, hikes, or works most days", bars: 3),
    ]

    // MARK: Derived

    var dogDisplayName: String {
        let t = dogName.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Bella" : t
    }

    var ageLabel: String {
        if ageMonths < 12 { return "\(ageMonths) mo" }
        let yrs = ageMonths / 12, mos = ageMonths % 12
        return mos == 0 ? "\(yrs) yr" : "\(yrs) yr \(mos) mo"
    }

    var weightDisplay: String {
        if unitKg {
            return weightKg.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(weightKg)) : String(format: "%.1f", weightKg)
        }
        return String(format: "%.1f", weightKg * 2.2046)
    }

    var unitLabel: String { unitKg ? "kg" : "lb" }

    var neuterLabel: String { sexFemale ? "Spayed" : "Neutered" }

    var progressPct: CGFloat {
        if step < 1 { return 0 }
        if step >= 9 { return 100 }
        return CGFloat((Double(step) / 9.0 * 100).rounded())
    }

    /// The design's daily-target formula (kept exactly so the reveal matches).
    func targetKcal() -> Int {
        let rer = 70 * pow(max(1, weightKg), 0.75)
        let nf = neutered ? 1.6 : 1.8
        let af = [1.2, 1.5, 1.9][activity]
        let bcsAdj = [1.15, 1.05, 1.0, 0.92, 0.85][bcs]
        return Int((rer * nf * af * bcsAdj / 10).rounded()) * 10
    }

    // MARK: Actions

    func stepForward() { go(step + 1) }
    func back() { go(step - 1) }

    func go(_ n: Int) {
        withAnimation(.timingCurve(0.42, 0, 0.15, 1, duration: 0.48)) {
            step = max(0, min(11, n))
        }
    }

    func ageUp()   { ageMonths = min(300, ageMonths + (ageMonths < 12 ? 1 : 12)) }
    func ageDown() { ageMonths = max(1, ageMonths - (ageMonths <= 12 ? 1 : 12)) }

    func setWeight(_ v: Double) { weightKg = min(80, max(2, (v * 2).rounded() / 2)) }

    func toggleAllergen(_ name: String) {
        if let i = allergens.firstIndex(of: name) { allergens.remove(at: i) }
        else { allergens.append(name) }
    }

    var filteredBreeds: [(name: String, size: String)] {
        let q = breedQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? breeds : breeds.filter { $0.name.lowercased().contains(q) }
    }

    var suggestedAllergens: [String] {
        let q = allergenQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return allergenOptions.filter {
            !allergens.contains($0) && (q.isEmpty || $0.lowercased().contains(q))
        }
    }

    func reset() {
        step = 0; mode = .new
        householdName = ""; inviteCode = ""
        dogName = ""; dogPhoto = false; breed = nil; breedSize = ""
        ageMonths = 24; sexFemale = true; neutered = true
        weightKg = 28; unitKg = true; bcs = 2; activity = 1; allergens = []
        breedQuery = ""; allergenQuery = ""
    }

    // MARK: Mapping to the app model

    private func canonicalAllergen(_ name: String) -> String {
        let base = name.lowercased().split(separator: "/").first.map(String.init) ?? name.lowercased()
        return base.trimmingCharacters(in: .whitespaces)
    }

    func buildDog() -> Dog {
        let bodyMap: [BodyCondition] = [.veryLean, .lean, .ideal, .overweight, .obese]
        let bc = bodyMap[bcs]

        let stage: LifeStage
        if activity == 2 { stage = .active }
        else if !neutered { stage = .intactAdult }
        else if activity == 0 { stage = .proneToObesity }
        else { stage = .neuteredAdult }

        // If the dog is carrying weight, nudge the ideal target below current.
        let idealFactor: Double = [1.05, 1.0, 1.0, 0.9, 0.82][bcs]

        let allergenObjs = allergens.map {
            Allergen(canonical: canonicalAllergen($0), severity: .hard)
        }

        return Dog(
            name: dogDisplayName,
            emoji: "🐶",
            avatar: [0xF6D9A0, 0xEBB25E],
            breed: breed ?? "Mixed breed",
            ageYears: max(0, ageMonths / 12),
            weightKg: weightKg,
            idealWeightKg: (weightKg * idealFactor * 10).rounded() / 10,
            bodyCondition: bc,
            lifeStage: stage,
            allergens: allergenObjs,
            targetOverride: targetKcal())
    }
}
