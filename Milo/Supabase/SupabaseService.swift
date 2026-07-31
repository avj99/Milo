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
    var proteinG: Double?
    var fatG: Double?
    var fiberG: Double?
    var moistureG: Double?
    enum CodingKeys: String, CodingKey {
        case id, householdId = "household_id", name, brand, emoji, category
        case kcalPerUnit = "kcal_per_unit", portionBasis = "portion_basis"
        case ingredients, verified, isEstimate = "is_estimate"
        case proteinG = "protein_g", fatG = "fat_g"
        case fiberG = "fiber_g", moistureG = "moisture_g"
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

// MARK: - Insert payloads
// The client supplies the row id so local and cloud share the same UUIDs —
// that makes the local JSON cache a faithful mirror and every push idempotent.

struct NewDog: Encodable {
    var id: UUID
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

struct NewDogAllergen: Encodable {
    var id: UUID
    var dogId: UUID
    var canonical: String
    var severity: String
    enum CodingKeys: String, CodingKey { case id, dogId = "dog_id", canonical, severity }
}

struct NewProduct: Encodable {
    var id: UUID
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
    var proteinG: Double?
    var fatG: Double?
    var fiberG: Double?
    var moistureG: Double?
    var createdBy: UUID?
    enum CodingKeys: String, CodingKey {
        case id, householdId = "household_id", name, brand, emoji, category
        case kcalPerUnit = "kcal_per_unit", portionBasis = "portion_basis"
        case ingredients, verified, isEstimate = "is_estimate"
        case proteinG = "protein_g", fatG = "fat_g"
        case fiberG = "fiber_g", moistureG = "moisture_g"
        case createdBy = "created_by"
    }
}

struct NewLogEntry: Encodable {
    var id: UUID
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

    // MARK: Auth (email + password)

    /// Signs in an existing account.
    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    /// Creates an account. If the project has "Confirm email" enabled the
    /// returned session is nil until the user confirms; with it disabled the
    /// user is signed in immediately.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        let response = try await client.auth.signUp(email: email, password: password)
        return response.session != nil     // true = signed in now
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

    /// Syncs the signed-in user's display name to their member row.
    /// (Only exists once they belong to a household; safe no-op otherwise.)
    func updateMyMemberName(_ name: String) async throws {
        guard let uid = currentUserID else { return }
        try await client.from("members")
            .update(["display_name": name,
                     "initials": String(name.prefix(1)).uppercased()])
            .eq("user_id", value: uid)
            .execute()
    }

    // MARK: Dogs

    func dogs() async throws -> [DogDTO] {
        try await client.from("dogs").select().order("created_at").execute().value
    }

    /// All allergens for the household's dogs (RLS scopes automatically).
    func allergens() async throws -> [DogAllergenDTO] {
        try await client.from("dog_allergens").select().execute().value
    }

    func insertDog(_ dog: NewDog, allergens: [NewDogAllergen]) async throws {
        try await client.from("dogs").upsert(dog, onConflict: "id").execute()
        if !allergens.isEmpty {
            try await client.from("dog_allergens")
                .upsert(allergens, onConflict: "id").execute()
        }
    }

    // MARK: Products

    func products() async throws -> [ProductDTO] {
        try await client.from("products").select().order("created_at", ascending: false).execute().value
    }

    /// Idempotent: logging the same favourite twice just re-upserts it.
    func upsertProduct(_ product: NewProduct) async throws {
        try await client.from("products").upsert(product, onConflict: "id").execute()
    }

    /// Removes a fridge item. Log entries keep their snapshot (product_id is
    /// ON DELETE SET NULL server-side).
    func deleteProduct(id: UUID) async throws {
        try await client.from("products").delete().eq("id", value: id).execute()
    }

    // MARK: Log

    /// Today's entries across the whole household (RLS scopes to it).
    func todayLog() async throws -> [LogEntryDTO] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return try await client.from("log_entries")
            .select()
            .gte("logged_at", value: startOfDay.ISO8601Format())
            .order("logged_at", ascending: false)
            .execute().value
    }

    /// "Capture once → assign to many": one insert per selected dog.
    func insertLogEntries(_ entries: [NewLogEntry]) async throws {
        guard !entries.isEmpty else { return }
        try await client.from("log_entries").upsert(entries, onConflict: "id").execute()
    }

    func deleteLogEntry(id: UUID) async throws {
        try await client.from("log_entries").delete().eq("id", value: id).execute()
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
