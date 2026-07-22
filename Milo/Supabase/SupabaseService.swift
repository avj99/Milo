import Foundation

// This file is gated on the Supabase SDK. Until you add the `supabase-swift`
// Swift Package (see Supabase/README-supabase.md), `canImport(Supabase)` is
// false and this whole file compiles to nothing — so the app keeps building.
// Once the package is added, the real client below comes alive.
#if canImport(Supabase)
import Supabase

// MARK: - Row DTOs (map Postgres snake_case ↔ Swift camelCase)

struct HouseholdDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var inviteCode: String
    enum CodingKeys: String, CodingKey { case id, name, inviteCode = "invite_code" }
}

struct MemberDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var householdId: UUID
    var userId: UUID
    var displayName: String
    var initials: String
    var palette: String
    enum CodingKeys: String, CodingKey {
        case id, householdId = "household_id", userId = "user_id"
        case displayName = "display_name", initials, palette
    }
}

struct DogDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var householdId: UUID
    var name: String
    var emoji: String
    var breed: String?
    var ageMonths: Int
    var sex: String
    var neutered: Bool
    var weightKg: Double
    var idealWeightKg: Double
    var bodyCondition: Int
    var lifeStage: String
    var activity: Int
    var targetOverride: Int?
    enum CodingKeys: String, CodingKey {
        case id, householdId = "household_id", name, emoji, breed
        case ageMonths = "age_months", sex, neutered
        case weightKg = "weight_kg", idealWeightKg = "ideal_weight_kg"
        case bodyCondition = "body_condition", lifeStage = "life_stage"
        case activity, targetOverride = "target_override"
    }
}

struct DogAllergenDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var dogId: UUID
    var canonical: String
    var severity: String
    enum CodingKeys: String, CodingKey { case id, dogId = "dog_id", canonical, severity }
}

struct ProductDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var householdId: UUID
    var name: String
    var brand: String
    var emoji: String
    var category: String
    var kcalPerUnit: Int
    var portionBasis: String
    var ingredients: [String]
    var verified: Bool
    var isEstimate: Bool
    enum CodingKeys: String, CodingKey {
        case id, householdId = "household_id", name, brand, emoji, category
        case kcalPerUnit = "kcal_per_unit", portionBasis = "portion_basis"
        case ingredients, verified, isEstimate = "is_estimate"
    }
}

struct LogEntryDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var householdId: UUID
    var dogId: UUID
    var productId: UUID?
    var portionCount: Int
    var kcal: Int
    var flaggedAllergen: Bool
    var loggedBy: UUID?
    var loggedAt: Date
    enum CodingKeys: String, CodingKey {
        case id, householdId = "household_id", dogId = "dog_id", productId = "product_id"
        case portionCount = "portion_count", kcal, flaggedAllergen = "flagged_allergen"
        case loggedBy = "logged_by", loggedAt = "logged_at"
    }
}

// MARK: - Insert payloads (no id / server-defaulted columns)

struct NewDog: Encodable {
    var householdId: UUID
    var name: String
    var emoji: String
    var breed: String?
    var ageMonths: Int
    var sex: String
    var neutered: Bool
    var weightKg: Double
    var idealWeightKg: Double
    var bodyCondition: Int
    var lifeStage: String
    var activity: Int
    var targetOverride: Int?
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id", name, emoji, breed
        case ageMonths = "age_months", sex, neutered
        case weightKg = "weight_kg", idealWeightKg = "ideal_weight_kg"
        case bodyCondition = "body_condition", lifeStage = "life_stage"
        case activity, targetOverride = "target_override"
    }
}

struct NewLogEntry: Encodable {
    var householdId: UUID
    var dogId: UUID
    var productId: UUID?
    var portionCount: Int
    var kcal: Int
    var flaggedAllergen: Bool
    var loggedBy: UUID?
    enum CodingKeys: String, CodingKey {
        case householdId = "household_id", dogId = "dog_id", productId = "product_id"
        case portionCount = "portion_count", kcal, flaggedAllergen = "flagged_allergen"
        case loggedBy = "logged_by"
    }
}

// MARK: - Service

/// Thin wrapper over the Supabase client with the queries Milo needs.
/// RLS scopes every query to the signed-in user's household automatically.
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client = SupabaseClient(
        supabaseURL: SupabaseConfig.url,
        supabaseKey: SupabaseConfig.publishableKey)

    var currentUserID: UUID? { client.auth.currentUser?.id }
    var isSignedIn: Bool { client.auth.currentUser != nil }

    // MARK: Auth (Sign in with Apple)

    /// Pass the identity token + raw nonce from ASAuthorizationAppleIDCredential.
    func signInWithApple(idToken: String, nonce: String) async throws {
        try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
    }

    func signOut() async throws { try await client.auth.signOut() }

    /// Deletes the user's own membership. App Store requires in-app account
    /// deletion; a full user delete also needs a server-side admin call.
    func leaveHousehold(memberID: UUID) async throws {
        try await client.from("members").delete().eq("id", value: memberID).execute()
    }

    // MARK: Household

    func createHousehold(name: String, memberName: String) async throws -> HouseholdDTO {
        try await client
            .rpc("create_household", params: ["hh_name": name, "member_name": memberName])
            .single().execute().value
    }

    func joinHousehold(code: String, memberName: String) async throws -> HouseholdDTO {
        try await client
            .rpc("join_household", params: ["code": code, "member_name": memberName])
            .single().execute().value
    }

    /// The current user's household (RLS returns only theirs).
    func myHousehold() async throws -> HouseholdDTO? {
        let rows: [HouseholdDTO] = try await client.from("households")
            .select().limit(1).execute().value
        return rows.first
    }

    func members() async throws -> [MemberDTO] {
        try await client.from("members").select().execute().value
    }

    // MARK: Dogs

    func dogs() async throws -> [DogDTO] {
        try await client.from("dogs").select().order("created_at").execute().value
    }

    func allergens(dogID: UUID) async throws -> [DogAllergenDTO] {
        try await client.from("dog_allergens").select().eq("dog_id", value: dogID).execute().value
    }

    func insertDog(_ dog: NewDog) async throws -> DogDTO {
        try await client.from("dogs").insert(dog).single().execute().value
    }

    // MARK: Products

    func products() async throws -> [ProductDTO] {
        try await client.from("products").select().order("created_at", ascending: false).execute().value
    }

    // MARK: Log

    /// Today's entries for a dog (RLS scopes to the household).
    func todayLog(dogID: UUID) async throws -> [LogEntryDTO] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return try await client.from("log_entries")
            .select()
            .eq("dog_id", value: dogID)
            .gte("logged_at", value: startOfDay.ISO8601Format())
            .order("logged_at", ascending: false)
            .execute().value
    }

    /// "Capture once → assign to many": one insert per selected dog.
    func insertLogEntries(_ entries: [NewLogEntry]) async throws {
        try await client.from("log_entries").insert(entries).execute()
    }

    // MARK: Realtime — the live shared dashboard

    /// Streams inserts into `log_entries` for a household. Usage:
    /// ```
    /// let channel = service.householdChannel(householdID: id)
    /// let inserts = channel.postgresChange(InsertAction.self, schema: "public",
    ///     table: "log_entries", filter: "household_id=eq.\(id)")
    /// await channel.subscribe()
    /// for await _ in inserts { await reload() }
    /// ```
    func householdChannel(householdID: UUID) -> RealtimeChannelV2 {
        client.channel("household-\(householdID.uuidString)")
    }
}
#endif
