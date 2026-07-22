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

    /// The signed-in user. A local stand-in until Supabase auth lands; persisted.
    private(set) var you: Member

    private let persistence = LocalStore()

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
    }

    // MARK: - Derived

    func dog(_ id: UUID) -> Dog? { dogs.first { $0.id == id } }

    func entries(for dogID: UUID) -> [LogEntry] {
        log.filter { $0.dogID == dogID }.sorted { $0.time > $1.time }
    }

    func consumed(for dogID: UUID) -> Int {
        log.filter { $0.dogID == dogID }.reduce(0) { $0 + $1.kcal }
    }

    func remaining(for dog: Dog) -> Int { dog.dailyTarget - consumed(for: dog.id) }

    func progress(for dog: Dog) -> Double {
        guard dog.dailyTarget > 0 else { return 0 }
        return Double(consumed(for: dog.id)) / Double(dog.dailyTarget)
    }

    /// Share of today's calories that came from treats/add-ins.
    func treatPercent(for dogID: UUID) -> Int {
        let total = consumed(for: dogID)
        guard total > 0 else { return 0 }
        let treats = log
            .filter { $0.dogID == dogID && $0.product.category != .meal }
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
    }

    /// Local stub — a real join needs the backend to resolve the code.
    func joinHousehold(code: String) {
        household = Household(name: "Shared household",
                              inviteCode: code.uppercased(),
                              members: members)
        save()
    }

    func addOnboardedDog(_ dog: Dog) {
        dogs.append(dog)
        save()
    }

    /// Sets the current user's display name (e.g. from Sign in with Apple).
    func updateCurrentUser(name: String) {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        you.name = clean
        you.initials = String(clean.prefix(1)).uppercased()
        if let i = members.firstIndex(where: { $0.isYou }) { members[i] = you }
        save()
    }

    // MARK: - Logging

    /// "Capture once → assign to many": one entry per selected dog, each with its
    /// own portion, calorie result, and allergy check. The product is also kept
    /// in favourites so it's one tap to log again.
    func logProduct(_ product: Product,
                    to assignments: [(dog: Dog, portionCount: Int)],
                    by member: Member) {
        var added: [LogEntry] = []
        for a in assignments {
            let kcal = product.kcalPerUnit * a.portionCount
            let flagged = AllergenEngine.hasHardFlag(for: a.dog, product: product)
            added.append(LogEntry(
                dogID: a.dog.id, product: product, portionCount: a.portionCount,
                time: Date(), loggedBy: member, kcal: kcal, flaggedAllergen: flagged))
        }
        log.append(contentsOf: added)
        rememberFavorite(product)
        save()

        let names = assignments.map(\.dog.name)
        let msg: String
        switch names.count {
        case 0:  msg = "Nothing logged"
        case 1:  msg = "Logged to \(names[0]) · saved"
        default: msg = "Logged to \(names.count) dogs · saved"
        }
        showToast(msg)
    }

    /// Keep a product in the reusable favourites list (dedup by name + brand).
    func rememberFavorite(_ product: Product) {
        let exists = favorites.contains {
            $0.name.caseInsensitiveCompare(product.name) == .orderedSame && $0.brand == product.brand
        }
        guard !exists else { return }
        favorites.insert(product, at: 0)
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if toast == text { toast = nil }
        }
    }

    /// Wipes all local data and returns to a fresh, un-onboarded state.
    func resetAll() {
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

    static func generateInviteCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return "MILO-" + String((0..<4).map { _ in alphabet.randomElement()! })
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
