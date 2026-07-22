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
    var ageYears: Int
    /// Current weight in kg.
    var weightKg: Double
    /// Ideal / target weight used by the calorie formula.
    var idealWeightKg: Double
    var bodyCondition: BodyCondition
    var lifeStage: LifeStage
    var allergens: [Allergen]
    /// A target set directly during onboarding. When present it wins over the
    /// engine's estimate, so the number shown on the dashboard matches the one
    /// the owner saw in the onboarding reveal.
    var targetOverride: Int?

    init(id: UUID = UUID(), name: String, emoji: String, avatar: [UInt],
         breed: String, ageYears: Int, weightKg: Double, idealWeightKg: Double,
         bodyCondition: BodyCondition, lifeStage: LifeStage, allergens: [Allergen],
         targetOverride: Int? = nil) {
        self.id = id; self.name = name; self.emoji = emoji; self.avatar = avatar
        self.breed = breed; self.ageYears = ageYears; self.weightKg = weightKg
        self.idealWeightKg = idealWeightKg; self.bodyCondition = bodyCondition
        self.lifeStage = lifeStage; self.allergens = allergens
        self.targetOverride = targetOverride
    }

    var avatarGradient: LinearGradient {
        LinearGradient(colors: avatar.map { Color(hex: $0) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Daily calorie target (MER), rounded to a tidy number.
    var dailyTarget: Int { targetOverride ?? CalorieEngine.dailyTarget(for: self) }

    var subtitle: String { "\(breed) · \(ageYears) yr · \(Int(weightKg)) kg" }
}

// MARK: - Product

enum FoodCategory: String, CaseIterable, Identifiable, Codable {
    case meal, treat, addIn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .meal:  return "Meal"
        case .treat: return "Treat"
        case .addIn: return "Human add-in"
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

    init(id: UUID = UUID(), name: String, brand: String, emoji: String,
         category: FoodCategory, kcalPerUnit: Int, portionBasis: String,
         ingredients: [String], verified: Bool = true, isEstimate: Bool = false) {
        self.id = id; self.name = name; self.brand = brand; self.emoji = emoji
        self.category = category; self.kcalPerUnit = kcalPerUnit
        self.portionBasis = portionBasis; self.ingredients = ingredients
        self.verified = verified; self.isEstimate = isEstimate
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
