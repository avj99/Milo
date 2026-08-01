import SwiftUI
import Combine

/// The app's data store. Starts empty and holds only real data the user adds —
/// the household + dog created during onboarding, and foods/logs captured in
/// the app. Everything is persisted locally (JSON in Application Support) so it
/// survives relaunches, and mirrors the shape of the Supabase backend so the
/// cloud sync layer can drop in later (see Supabase/README-supabase.md).
@MainActor
final class AppStore: ObservableObject {

    @Published var household: Household?     // nil until onboarding creates one
    @Published var members: [Member]
    @Published var dogs: [Dog] = []
    @Published var log: [LogEntry] = []      // all entries, all dogs
    @Published var favorites: [Product] = [] // reusable foods you've added

    @Published var toast: String? = nil

    /// The signed-in user. Adopted from the cloud member row when signed in;
    /// a local stand-in otherwise. Persisted.
    private(set) var you: Member

    private let persistence = LocalStore()

    /// Cloud sync (Supabase). A no-op stub when the SDK isn't linked. Local
    /// writes stay optimistic; this pushes them up and pulls the household in.
    private var cloud: CloudSync?

    /// True once a household exists — drives whether onboarding shows.
    var isSetUp: Bool { household != nil }
    var currentMember: Member { you }

    init() {
        if let snap = persistence.load() {
            you = snap.you
            members = snap.members
            household = snap.household
            dogs = snap.dogs
            log = snap.log
            favorites = snap.favorites
        } else {
            let you = Member(name: "You", initials: "Y", palette: .you, isYou: true)
            self.you = you
            self.members = [you]
            self.household = nil
        }
        let cloud = CloudSync(store: self)
        self.cloud = cloud
        cloud.start()

        #if DEBUG
        // Scripted end-to-end demo data for verification (fridge → log →
        // dashboard → trends). Only when launched with MILO_SCENARIO=demo.
        if ProcessInfo.processInfo.environment["MILO_SCENARIO"] == "demo" {
            DebugScenario.seedDemo(self)
        }
        #endif
    }

    // MARK: - Derived
    //
    // All daily numbers (ring, treats %, nutrients, the Today list) count
    // TODAY's entries only — the targets are per-day, so the rings must reset
    // at midnight. Older entries stay in `log` as history for Trends.

    func dog(_ id: UUID) -> Dog? { dogs.first { $0.id == id } }

    private func todaysEntries(for dogID: UUID) -> [LogEntry] {
        log.filter { $0.dogID == dogID && Calendar.current.isDateInToday($0.time) }
    }

    func entries(for dogID: UUID) -> [LogEntry] {
        todaysEntries(for: dogID).sorted { $0.time > $1.time }
    }

    func consumed(for dogID: UUID) -> Int {
        todaysEntries(for: dogID).reduce(0) { $0 + $1.kcal }
    }

    func remaining(for dog: Dog) -> Int { dog.dailyTarget - consumed(for: dog.id) }

    /// Grams of a nutrient logged today, via a Product key path. Missing
    /// product data counts as 0, so totals under-report rather than invent.
    func nutrientConsumedG(for dogID: UUID, _ keyPath: KeyPath<Product, Double?>) -> Int {
        Int(todaysEntries(for: dogID)
            .reduce(0.0) { $0 + ($1.product[keyPath: keyPath] ?? 0) * Double($1.portionCount) }
            .rounded())
    }

    func proteinConsumedG(for dogID: UUID) -> Int { nutrientConsumedG(for: dogID, \.proteinGPerUnit) }
    func fatConsumedG(for dogID: UUID) -> Int { nutrientConsumedG(for: dogID, \.fatGPerUnit) }
    func fiberConsumedG(for dogID: UUID) -> Int { nutrientConsumedG(for: dogID, \.fiberGPerUnit) }
    func moistureConsumedG(for dogID: UUID) -> Int { nutrientConsumedG(for: dogID, \.moistureGPerUnit) }

    func progress(for dog: Dog) -> Double {
        guard dog.dailyTarget > 0 else { return 0 }
        return Double(consumed(for: dog.id)) / Double(dog.dailyTarget)
    }

    /// Share of today's calories that came from treats/extras (anything that
    /// isn't a planned meal — kibble or wet food).
    func treatPercent(for dogID: UUID) -> Int {
        let total = consumed(for: dogID)
        guard total > 0 else { return 0 }
        let treats = todaysEntries(for: dogID)
            .filter { !$0.product.category.isMainMeal }
            .reduce(0) { $0 + $1.kcal }
        return Int((Double(treats) / Double(total) * 100).rounded())
    }

    /// Most recent entry for a dog — powers the "Live" strip.
    func latestActivity(for dogID: UUID) -> LogEntry? { entries(for: dogID).first }

    // MARK: - Setup (onboarding)

    func createHousehold(name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        household = Household(
            name: clean.isEmpty ? "My household" : clean,
            inviteCode: Self.generateInviteCode(),
            members: members)
        save()
        cloud?.didCreateHousehold()   // server invite code replaces the local one
    }

    /// Optimistic local household; when signed in the cloud join resolves the
    /// code and pulls the real household (name, members, dogs) over this stub.
    func joinHousehold(code: String) {
        household = Household(name: "Shared household",
                              inviteCode: code.uppercased(),
                              members: members)
        save()
        cloud?.didJoinHousehold(code: code.uppercased())
    }

    func addOnboardedDog(_ dog: Dog) {
        dogs.append(dog)
        save()
        cloud?.didAddDog(dog)
    }

    /// Sets the current user's display name (e.g. from Sign in with Apple).
    func updateCurrentUser(name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        you.name = clean
        you.initials = String(clean.prefix(1)).uppercased()
        if let i = members.firstIndex(where: { $0.isYou }) { members[i] = you }
        save()
        cloud?.didRenameUser(clean)
    }

    // MARK: - Cloud snapshot (CloudSync pull → store)

    /// Adopts the cloud's view of the household wholesale. Row ids are shared
    /// between local and cloud, so this also reconciles optimistic writes.
    /// The log becomes today's household entries (what the dashboard shows).
    func applyCloudSnapshot(household: Household, members: [Member],
                            dogs: [Dog], favorites: [Product], log: [LogEntry]) {
        self.household = household
        self.members = members
        if let me = members.first(where: { $0.isYou }) { self.you = me }
        self.dogs = dogs
        self.favorites = favorites
        self.log = log
        save()
    }

    // MARK: - Logging

    /// "Capture once → assign to many": one entry per selected dog, each with its
    /// own portion, calorie result, and allergy check. The product is also kept
    /// in favourites so it's one tap to log again.
    func logProduct(_ product: Product,
                    to assignments: [(dog: Dog, portionCount: Int)],
                    by member: Member) {
        // The fridge is the single source of products: logging the "same" food
        // twice reuses the existing product id, so duplicates can't be created
        // locally or in the cloud.
        let canonical = upsertFridgeItem(product)
        var added: [LogEntry] = []
        for a in assignments {
            let kcal = canonical.kcalPerUnit * a.portionCount
            let flagged = AllergenEngine.hasHardFlag(for: a.dog, product: canonical)
            added.append(LogEntry(
                dogID: a.dog.id, product: canonical, portionCount: a.portionCount,
                time: Date(), loggedBy: member, kcal: kcal, flaggedAllergen: flagged))
        }
        log.append(contentsOf: added)
        save()
        cloud?.didLog(entries: added, product: canonical)

        let names = assignments.map(\.dog.name)
        let msg: String
        switch names.count {
        case 0:  msg = "Nothing logged"
        case 1:  msg = "Logged to \(names[0]) · saved"
        default: msg = "Logged to \(names.count) dogs · saved"
        }
        showToast(msg)
    }

    // MARK: - My Fridge (the household's product database)

    /// Insert-or-merge by name + brand (case-insensitive). A match keeps the
    /// existing id and takes the newer details — never a duplicate row.
    @discardableResult
    func upsertFridgeItem(_ product: Product) -> Product {
        if let i = favorites.firstIndex(where: {
            $0.name.caseInsensitiveCompare(product.name) == .orderedSame
                && $0.brand.caseInsensitiveCompare(product.brand) == .orderedSame
        }) {
            let merged = Product(
                id: favorites[i].id,
                name: product.name, brand: product.brand, emoji: product.emoji,
                category: product.category, kcalPerUnit: product.kcalPerUnit,
                portionBasis: product.portionBasis, ingredients: product.ingredients,
                verified: product.verified, isEstimate: product.isEstimate,
                proteinGPerUnit: product.proteinGPerUnit ?? favorites[i].proteinGPerUnit,
                fatGPerUnit: product.fatGPerUnit ?? favorites[i].fatGPerUnit,
                fiberGPerUnit: product.fiberGPerUnit ?? favorites[i].fiberGPerUnit,
                moistureGPerUnit: product.moistureGPerUnit ?? favorites[i].moistureGPerUnit)
            favorites[i] = merged
            return merged
        }
        favorites.insert(product, at: 0)
        return product
    }

    /// "Add to Fridge" without logging — saves the foods for later use.
    func addToFridge(_ products: [Product]) {
        let saved = products.map { upsertFridgeItem($0) }
        save()
        cloud?.didSaveProducts(saved)
        showToast(saved.count == 1 ? "Added to My Fridge" : "\(saved.count) foods added to My Fridge")
    }

    func removeFromFridge(_ product: Product) {
        favorites.removeAll { $0.id == product.id }
        save()
        cloud?.didDeleteProduct(product.id)
    }

    /// Back-compat name used by older call sites.
    func rememberFavorite(_ product: Product) { upsertFridgeItem(product) }

    /// Removes a mistaken log entry (and its cloud row) — the rings correct
    /// themselves immediately.
    func deleteLogEntry(_ id: UUID) {
        guard log.contains(where: { $0.id == id }) else { return }
        log.removeAll { $0.id == id }
        save()
        cloud?.didDeleteLogEntry(id)
        showToast("Entry removed")
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast == text { toast = nil }
        }
    }

    /// Wipes all local data and returns to a fresh, un-onboarded state.
    /// Also signs out of the cloud so the next launch doesn't re-pull.
    func resetAll() {
        cloud?.didReset()
        persistence.clear()
        let you = Member(name: "You", initials: "Y", palette: .you, isYou: true)
        self.you = you
        members = [you]
        household = nil
        dogs = []
        log = []
        favorites = []
    }

    // MARK: - Persistence

    private func save() {
        persistence.save(StoreSnapshot(
            you: you, members: members, household: household,
            dogs: dogs, log: log, favorites: favorites))
    }

    /// 6-char code from an unambiguous alphabet — same format the backend's
    /// `gen_invite_code()` issues, so local and cloud codes look identical.
    static func generateInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in alphabet.randomElement()! })
    }
}

// MARK: - Local persistence

/// The persisted snapshot of everything the user has added.
struct StoreSnapshot: Codable {
    var you: Member
    var members: [Member]
    var household: Household?
    var dogs: [Dog]
    var log: [LogEntry]
    var favorites: [Product]
}

/// Reads/writes the snapshot as JSON under Application Support.
struct LocalStore {
    private var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("milo_store.json")
    }

    func load() -> StoreSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(StoreSnapshot.self, from: data)
    }

    func save(_ snapshot: StoreSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() { try? FileManager.default.removeItem(at: fileURL) }
}
