import SwiftUI

// The data model is deliberately shaped for multi-dog + shared household from
// day one, even though Phase 1 exercises only a slice of it. Per the build guide:
//   Household → Member → Dog → Product → LogEntry
// "Assign to many" spawns one LogEntry per dog, each with its own portion,
// its own calorie result against that dog's target, and its own allergy check.

// MARK: - Member

struct Member: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var initials: String
    var palette: MemberPalette
    var isYou: Bool = false

    init(id: UUID = UUID(), name: String, initials: String,
         palette: MemberPalette, isYou: Bool = false) {
        self.id = id; self.name = name; self.initials = initials
        self.palette = palette; self.isYou = isYou
    }
}

enum MemberPalette: String, Codable, Hashable {
    case mom, dad, kid, you

    var gradient: LinearGradient {
        let pair: [Color]
        switch self {
        case .mom: pair = [Theme.momA, Theme.momB]
        case .dad: pair = [Theme.dadA, Theme.dadB]
        case .kid: pair = [Theme.kidA, Theme.kidB]
        case .you: pair = [Theme.brand, Theme.brandDeep]
        }
        return LinearGradient(colors: pair, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Allergen

/// True allergy → a hard red flag; "vet said limit" → a soft nudge.
enum AllergenSeverity: String, Codable, Hashable {
    case hard   // real allergy
    case soft   // limit / caution

    var label: String { self == .hard ? "Allergy" : "Limit" }
}

struct Allergen: Identifiable, Hashable, Codable {
    let id: UUID
    /// Canonical name, e.g. "chicken", "beef", "wheat".
    var canonical: String
    var severity: AllergenSeverity

    init(id: UUID = UUID(), canonical: String, severity: AllergenSeverity = .hard) {
        self.id = id; self.canonical = canonical; self.severity = severity
    }

    var display: String { canonical.capitalized }
}

// MARK: - Body condition + life stage (feed the calorie engine)

/// The 9-point body-condition scale, simplified to the buckets the UI shows.
/// BCS is a more reliable signal than breed, so it is a first-class input.
enum BodyCondition: Int, CaseIterable, Identifiable, Codable {
    case veryLean = 2, lean = 3, ideal = 5, overweight = 7, obese = 9
    var id: Int { rawValue }

    var short: String {
        switch self {
        case .veryLean: return "2"
        case .lean:     return "3"
        case .ideal:    return "5"
        case .overweight: return "7"
        case .obese:    return "9"
        }
    }

    var caption: String {
        switch self {
        case .veryLean: return "Very lean — ribs visible"
        case .lean:     return "Lean — ribs easily felt"
        case .ideal:    return "Ideal — ribs felt, not seen"
        case .overweight: return "Overweight — ribs hard to feel"
        case .obese:    return "Heavy — discuss a plan with your vet"
        }
    }
}

/// Life-stage / activity factor applied to RER to get the daily target (MER).
/// Published factors vary by source; these are tunable defaults, not gospel.
enum LifeStage: String, CaseIterable, Identifiable, Codable {
    case neuteredAdult, intactAdult, proneToObesity, weightLoss, active
    case puppyYoung, puppyOld
    var id: String { rawValue }

    var factor: Double {
        switch self {
        case .neuteredAdult:  return 1.6
        case .intactAdult:    return 1.8
        case .proneToObesity: return 1.3
        case .weightLoss:     return 1.0
        case .active:         return 2.0
        case .puppyYoung:     return 3.0
        case .puppyOld:       return 2.0
        }
    }

    var label: String {
        switch self {
        case .neuteredAdult:  return "Neutered adult"
        case .intactAdult:    return "Intact adult"
        case .proneToObesity: return "Prone to obesity / senior"
        case .weightLoss:     return "Weight loss"
        case .active:         return "Active / working"
        case .puppyYoung:     return "Puppy · 0–4 mo"
        case .puppyOld:       return "Puppy · 4 mo–adult"
        }
    }

    var short: String {
        switch self {
        case .active: return "active"
        case .weightLoss: return "weight loss"
        case .proneToObesity: return "senior"
        default: return "adult"
        }
    }
}

// MARK: - Dog

struct Dog: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String
    var avatar: [UInt]           // gradient pair (hex) for the avatar tile
    var breed: String
    /// Age in months — kept in months so the calorie engine can tell a growing
    /// puppy (which needs a different formula) from an adult.
    var ageMonths: Int
    /// Current weight in kg.
    var weightKg: Double
    /// Ideal / target weight used by the adult calorie formula.
    var idealWeightKg: Double
    var bodyCondition: BodyCondition
    var lifeStage: LifeStage
    var allergens: [Allergen]
    /// A target set directly during onboarding. When present it wins over the
    /// engine's estimate, so the number shown on the dashboard matches the one
    /// the owner saw in the onboarding reveal.
    var targetOverride: Int?

    init(id: UUID = UUID(), name: String, emoji: String, avatar: [UInt],
         breed: String, ageMonths: Int, weightKg: Double, idealWeightKg: Double,
         bodyCondition: BodyCondition, lifeStage: LifeStage, allergens: [Allergen],
         targetOverride: Int? = nil) {
        self.id = id; self.name = name; self.emoji = emoji; self.avatar = avatar
        self.breed = breed; self.ageMonths = ageMonths; self.weightKg = weightKg
        self.idealWeightKg = idealWeightKg; self.bodyCondition = bodyCondition
        self.lifeStage = lifeStage; self.allergens = allergens
        self.targetOverride = targetOverride
    }

    var ageYears: Int { ageMonths / 12 }

    var ageText: String {
        if ageMonths < 12 { return "\(ageMonths) mo" }
        let y = ageMonths / 12, m = ageMonths % 12
        return m == 0 ? "\(y) yr" : "\(y) yr \(m) mo"
    }

    var avatarGradient: LinearGradient {
        LinearGradient(colors: avatar.map { Color(hex: $0) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Daily calorie target, rounded. Uses the engine unless a target was set.
    var dailyTarget: Int { targetOverride ?? CalorieEngine.dailyTarget(for: self) }

    /// True while the dog is still on the puppy growth curve (breed-aware).
    var isGrowing: Bool {
        let maturity = BreedCatalog.find(breed)?.size.maturityMonths ?? 12
        return ageMonths < maturity
    }

    var subtitle: String { "\(breed) · \(ageText) · \(Int(weightKg)) kg" }
}

// MARK: - Product

enum FoodCategory: String, CaseIterable, Identifiable, Codable {
    case kibble, wet, treat, meat, fish, vegetable, fruit, dairy, grain, supplement, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .kibble:     return "Kibble"
        case .wet:        return "Wet food"
        case .treat:      return "Treat"
        case .meat:       return "Meat"
        case .fish:       return "Fish"
        case .vegetable:  return "Vegetable"
        case .fruit:      return "Fruit"
        case .dairy:      return "Dairy & egg"
        case .grain:      return "Grains"
        case .supplement: return "Supplement"
        case .other:      return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .kibble:     return "🥣"
        case .wet:        return "🥫"
        case .treat:      return "🦴"
        case .meat:       return "🥩"
        case .fish:       return "🐟"
        case .vegetable:  return "🥕"
        case .fruit:      return "🍎"
        case .dairy:      return "🥚"
        case .grain:      return "🍚"
        case .supplement: return "💊"
        case .other:      return "🍽️"
        }
    }

    /// Kibble and wet food are the planned meals; everything else counts
    /// toward the treats/extras share of the day.
    var isMainMeal: Bool { self == .kibble || self == .wet }

    /// Decodes legacy values ("meal", "addIn") from old saved stores and old
    /// cloud rows, so nothing breaks when the taxonomy grows.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodCategory(legacy: raw)
    }

    init(legacy raw: String) {
        switch raw {
        case "meal":  self = .kibble
        case "addIn": self = .other
        default:      self = FoodCategory(rawValue: raw) ?? .other
        }
    }
}

/// The food itself — shared and reusable, captured once.
struct Product: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var brand: String
    var emoji: String
    var category: FoodCategory
    /// Calories per unit of `portionBasis` (always stored as kilocalories).
    var kcalPerUnit: Int
    /// e.g. "piece", "¾ cup", "handful".
    var portionBasis: String
    /// Canonical ingredient names, normalized for the allergy engine.
    var ingredients: [String]
    /// Crowdsourced entries enter unverified until corroborated.
    var verified: Bool
    /// Human add-ins / photo estimates are shown as ranges, not false precision.
    var isEstimate: Bool
    /// Grams per one `portionBasis` unit for the guaranteed-analysis panel
    /// (crude protein, crude fat, crude fiber, moisture) — from the label or a
    /// nutrition estimate. Optional — older entries and quick adds may not
    /// have them; daily math treats missing as 0 (under-report, never invent).
    var proteinGPerUnit: Double?
    var fatGPerUnit: Double?
    var fiberGPerUnit: Double?
    var moistureGPerUnit: Double?

    init(id: UUID = UUID(), name: String, brand: String, emoji: String,
         category: FoodCategory, kcalPerUnit: Int, portionBasis: String,
         ingredients: [String], verified: Bool = true, isEstimate: Bool = false,
         proteinGPerUnit: Double? = nil, fatGPerUnit: Double? = nil,
         fiberGPerUnit: Double? = nil, moistureGPerUnit: Double? = nil) {
        self.id = id; self.name = name; self.brand = brand; self.emoji = emoji
        self.category = category; self.kcalPerUnit = kcalPerUnit
        self.portionBasis = portionBasis; self.ingredients = ingredients
        self.verified = verified; self.isEstimate = isEstimate
        self.proteinGPerUnit = proteinGPerUnit; self.fatGPerUnit = fatGPerUnit
        self.fiberGPerUnit = fiberGPerUnit; self.moistureGPerUnit = moistureGPerUnit
    }
}

// MARK: - Log entry

/// Links one product to one dog at a time, with a portion, and records who logged it.
struct LogEntry: Identifiable, Hashable, Codable {
    let id: UUID
    var dogID: UUID
    var product: Product
    var portionCount: Int
    var time: Date
    var loggedBy: Member
    /// Snapshot of the calorie result for this dog at log time.
    var kcal: Int
    var flaggedAllergen: Bool

    init(id: UUID = UUID(), dogID: UUID, product: Product, portionCount: Int,
         time: Date, loggedBy: Member, kcal: Int, flaggedAllergen: Bool) {
        self.id = id; self.dogID = dogID; self.product = product
        self.portionCount = portionCount; self.time = time; self.loggedBy = loggedBy
        self.kcal = kcal; self.flaggedAllergen = flaggedAllergen
    }

    var portionText: String {
        let unit = product.portionBasis
        if unit == "piece" { return "\(portionCount) " + (portionCount == 1 ? "piece" : "pieces") }
        return portionCount == 1 ? unit : "\(portionCount)× \(unit)"
    }
}

// MARK: - Household

struct Household: Identifiable, Codable {
    let id: UUID
    var name: String
    var inviteCode: String
    var members: [Member]

    init(id: UUID = UUID(), name: String, inviteCode: String, members: [Member]) {
        self.id = id; self.name = name; self.inviteCode = inviteCode; self.members = members
    }
}
