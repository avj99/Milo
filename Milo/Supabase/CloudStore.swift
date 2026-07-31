import Foundation

// The SupabaseStore adapter: maps DTOs ↔ app models and keeps AppStore in sync
// with the cloud. Local JSON (LocalStore) stays as the offline cache — the app
// works fully offline; when signed in, the cloud is the source of truth.
//
// Sync rules:
//  - Signed in + cloud household exists  → pull; cloud wins, local becomes cache.
//  - Signed in + only local household    → push local up once (migration), re-pull.
//  - Not signed in                       → local-only, exactly as before.
// Writes are optimistic: AppStore applies them locally first, then hands them
// to CloudSync, which pushes in order on a serial chain (so "create household"
// always lands before "add dog"). Row ids are client-generated, so pushes are
// idempotent upserts and pulls line up with what's already cached locally.
#if canImport(Supabase)
import Supabase

// MARK: - DTO ↔ model mapping

enum CloudMap {

    // The avatar gradient isn't stored server-side; onboarding currently gives
    // every dog the same pair, so cloud dogs get it too.
    static let defaultAvatar: [UInt] = [0xF6D9A0, 0xEBB25E]

    static func member(_ dto: MemberDTO, currentUserID: UUID?) -> Member {
        Member(id: dto.id,
               name: dto.displayName,
               initials: dto.initials,
               palette: MemberPalette(rawValue: dto.palette) ?? .you,
               isYou: dto.userId == currentUserID)
    }

    /// Server allows BCS 1–9; the app models the five UI buckets.
    static func bcs(_ raw: Int) -> BodyCondition {
        BodyCondition.allCases.min {
            abs($0.rawValue - raw) < abs($1.rawValue - raw)
        } ?? .ideal
    }

    static func dog(_ dto: DogDTO, allergens: [DogAllergenDTO]) -> Dog {
        Dog(id: dto.id,
            name: dto.name,
            emoji: dto.emoji,
            avatar: defaultAvatar,
            breed: dto.breed ?? "Mixed / unknown",
            ageMonths: dto.ageMonths,
            weightKg: dto.weightKg,
            idealWeightKg: dto.idealWeightKg,
            bodyCondition: bcs(dto.bodyCondition),
            lifeStage: LifeStage(rawValue: dto.lifeStage) ?? .neuteredAdult,
            allergens: allergens.map {
                Allergen(id: $0.id, canonical: $0.canonical,
                         severity: AllergenSeverity(rawValue: $0.severity) ?? .hard)
            },
            targetOverride: dto.targetOverride)
    }

    static func newDog(_ dog: Dog, householdID: UUID) -> NewDog {
        NewDog(id: dog.id,
               householdId: householdID,
               name: dog.name,
               emoji: dog.emoji,
               breed: dog.breed,
               ageMonths: dog.ageMonths,
               // Sex isn't kept on the app model (it only feeds lifeStage
               // during onboarding), so the column takes its default.
               sex: "female",
               neutered: dog.lifeStage != .intactAdult,
               weightKg: dog.weightKg,
               idealWeightKg: dog.idealWeightKg,
               bodyCondition: dog.bodyCondition.rawValue,
               lifeStage: dog.lifeStage.rawValue,
               activity: dog.lifeStage == .active ? 2
                       : dog.lifeStage == .proneToObesity ? 0 : 1,
               targetOverride: dog.targetOverride)
    }

    static func newAllergens(_ dog: Dog) -> [NewDogAllergen] {
        dog.allergens.map {
            NewDogAllergen(id: $0.id, dogId: dog.id,
                           canonical: $0.canonical, severity: $0.severity.rawValue)
        }
    }

    static func product(_ dto: ProductDTO) -> Product {
        Product(id: dto.id,
                name: dto.name,
                brand: dto.brand,
                emoji: dto.emoji,
                category: FoodCategory(legacy: dto.category),
                kcalPerUnit: dto.kcalPerUnit,
                portionBasis: dto.portionBasis,
                ingredients: dto.ingredients,
                verified: dto.verified,
                isEstimate: dto.isEstimate,
                proteinGPerUnit: dto.proteinG,
                fatGPerUnit: dto.fatG,
                fiberGPerUnit: dto.fiberG,
                moistureGPerUnit: dto.moistureG)
    }

    static func newProduct(_ p: Product, householdID: UUID, createdBy: UUID?) -> NewProduct {
        NewProduct(id: p.id,
                   householdId: householdID,
                   name: p.name,
                   brand: p.brand,
                   emoji: p.emoji,
                   category: p.category.rawValue,
                   kcalPerUnit: p.kcalPerUnit,
                   portionBasis: p.portionBasis,
                   ingredients: p.ingredients,
                   verified: p.verified,
                   isEstimate: p.isEstimate,
                   proteinG: p.proteinGPerUnit,
                   fatG: p.fatGPerUnit,
                   fiberG: p.fiberGPerUnit,
                   moistureG: p.moistureGPerUnit,
                   createdBy: createdBy)
    }

    /// Rebuilds a LogEntry from its row + the household's products and members.
    /// `members` is keyed by auth user id (what `logged_by` stores).
    static func entry(_ dto: LogEntryDTO,
                      products: [UUID: Product],
                      membersByUser: [UUID: Member]) -> LogEntry {
        let product = dto.productId.flatMap { products[$0] }
            ?? Product(name: "Logged food", brand: "", emoji: "🍽️",
                       category: .other, kcalPerUnit: dto.kcal,
                       portionBasis: "serving", ingredients: [])
        let member = dto.loggedBy.flatMap { membersByUser[$0] }
            ?? Member(name: "Household member", initials: "H", palette: .you)
        return LogEntry(id: dto.id,
                        dogID: dto.dogId,
                        product: product,
                        portionCount: dto.portionCount,
                        time: dto.loggedAt,
                        loggedBy: member,
                        kcal: dto.kcal,
                        flaggedAllergen: dto.flaggedAllergen)
    }

    static func newEntry(_ e: LogEntry, householdID: UUID, loggedBy: UUID?) -> NewLogEntry {
        NewLogEntry(id: e.id,
                    householdId: householdID,
                    dogId: e.dogID,
                    productId: e.product.id,
                    portionCount: e.portionCount,
                    kcal: e.kcal,
                    flaggedAllergen: e.flaggedAllergen,
                    loggedBy: loggedBy,
                    loggedAt: e.time)
    }
}

// MARK: - Sync engine

@MainActor
final class CloudSync {
    unowned let store: AppStore
    private let service = SupabaseService.shared

    /// The cloud household we're bound to; nil until signed in + bootstrapped.
    private(set) var householdID: UUID?

    private var authTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var refreshDebounce: Task<Void, Never>?
    /// Serial chain: every push awaits the previous one, preserving order.
    private var chain: Task<Void, Never> = Task {}

    init(store: AppStore) { self.store = store }

    /// Watches auth: bootstrap on sign-in, detach on sign-out.
    func start() {
        authTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in service.client.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn:
                    if session != nil { await bootstrap() }
                case .signedOut:
                    detach()
                default:
                    break
                }
            }
        }
    }

    var isCloudBacked: Bool { householdID != nil }

    private func detach() {
        realtimeTask?.cancel(); realtimeTask = nil
        refreshDebounce?.cancel(); refreshDebounce = nil
        householdID = nil
    }

    // MARK: Bootstrap

    private func bootstrap() async {
        do {
            if let hh = try await service.myHousehold() {
                householdID = hh.id
                try await pull(hh)
                startRealtime(hh.id)
            } else if store.isSetUp {
                // Signed in with data created offline → migrate it up once.
                try await migrateLocal()
            }
            // Neither: onboarding will create/join a household shortly.
        } catch {
            // Stay on the local cache; realtime/bootstrap will retry on next
            // auth event or app launch.
            print("CloudSync bootstrap failed: \(error)")
        }
    }

    /// Pushes an offline-created household + its data to the cloud, then
    /// re-pulls so server-issued values (invite code) win.
    private func migrateLocal() async throws {
        let hh = try await service.createHousehold(
            name: store.household?.name ?? "My household",
            memberName: store.currentMember.name)
        householdID = hh.id
        let uid = service.currentUserID
        for dog in store.dogs {
            try await service.insertDog(CloudMap.newDog(dog, householdID: hh.id),
                                        allergens: CloudMap.newAllergens(dog))
        }
        for product in store.favorites {
            try await service.upsertProduct(
                CloudMap.newProduct(product, householdID: hh.id, createdBy: uid))
        }
        let today = Calendar.current.startOfDay(for: Date())
        try await service.insertLogEntries(store.log
            .filter { $0.time >= today }
            .map { CloudMap.newEntry($0, householdID: hh.id, loggedBy: uid) })
        try await pull(hh)
        startRealtime(hh.id)
    }

    // MARK: Pull (cloud → store)

    private func pull(_ hh: HouseholdDTO) async throws {
        async let membersReq = service.members()
        async let dogsReq = service.dogs()
        async let allergensReq = service.allergens()
        async let productsReq = service.products()
        async let logReq = service.todayLog()
        let (memberRows, dogRows, allergenRows, productRows, logRows) =
            try await (membersReq, dogsReq, allergensReq, productsReq, logReq)

        let uid = service.currentUserID
        let members = memberRows.map { CloudMap.member($0, currentUserID: uid) }
        let allergensByDog = Dictionary(grouping: allergenRows, by: \.dogId)
        let dogs = dogRows.map { CloudMap.dog($0, allergens: allergensByDog[$0.id] ?? []) }
        let favorites = productRows.map(CloudMap.product)

        let productsByID = Dictionary(uniqueKeysWithValues: favorites.map { ($0.id, $0) })
        let membersByUser = Dictionary(uniqueKeysWithValues: zip(memberRows.map(\.userId), members))
        let log = logRows.map {
            CloudMap.entry($0, products: productsByID, membersByUser: membersByUser)
        }

        store.applyCloudSnapshot(
            household: Household(id: hh.id, name: hh.name,
                                 inviteCode: hh.inviteCode, members: members),
            members: members,
            dogs: dogs,
            favorites: favorites,
            log: log)
    }

    /// Re-pull after a realtime event (debounced — events arrive in bursts).
    private func scheduleRefresh() {
        refreshDebounce?.cancel()
        refreshDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard let self, !Task.isCancelled else { return }
            if let hh = try? await service.myHousehold() { try? await pull(hh) }
        }
    }

    // MARK: Realtime

    private func startRealtime(_ householdID: UUID) {
        realtimeTask?.cancel()
        realtimeTask = Task { [weak self] in
            guard let self else { return }
            let channel = service.householdChannel(householdID: householdID)
            let filter = "household_id=eq.\(householdID.uuidString)"
            let logChanges = channel.postgresChange(AnyAction.self, schema: "public",
                                                    table: "log_entries", filter: filter)
            let dogChanges = channel.postgresChange(AnyAction.self, schema: "public",
                                                    table: "dogs", filter: filter)
            let memberChanges = channel.postgresChange(AnyAction.self, schema: "public",
                                                       table: "members", filter: filter)
            await channel.subscribe()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { for await _ in logChanges { await self.scheduleRefresh() } }
                group.addTask { for await _ in dogChanges { await self.scheduleRefresh() } }
                group.addTask { for await _ in memberChanges { await self.scheduleRefresh() } }
            }
            await service.client.removeChannel(channel)
        }
    }

    // MARK: Push hooks (store → cloud), serialized

    private func enqueue(_ label: String, _ op: @escaping () async throws -> Void) {
        guard service.isSignedIn else { return }
        chain = Task { [prev = chain] in
            await prev.value
            do { try await op() }
            catch { print("CloudSync \(label) failed: \(error)") }
        }
    }

    func didCreateHousehold() {
        enqueue("create household") { [self] in
            guard householdID == nil else { return }
            let hh = try await service.createHousehold(
                name: store.household?.name ?? "My household",
                memberName: store.currentMember.name)
            householdID = hh.id
            try await pull(hh)          // adopt server id + invite code
            startRealtime(hh.id)
        }
    }

    /// A real join: resolves the code server-side and pulls the household's
    /// existing dogs and log. On failure the local stub stays, with a toast.
    func didJoinHousehold(code: String) {
        enqueue("join household") { [self] in
            do {
                let hh = try await service.joinHousehold(
                    code: code, memberName: store.currentMember.name)
                householdID = hh.id
                try await pull(hh)
                startRealtime(hh.id)
            } catch {
                store.showToast("Couldn't join — check the invite code")
                throw error
            }
        }
    }

    func didAddDog(_ dog: Dog) {
        enqueue("add dog") { [self] in
            guard let hhID = householdID else { return }
            try await service.insertDog(CloudMap.newDog(dog, householdID: hhID),
                                        allergens: CloudMap.newAllergens(dog))
        }
    }

    func didLog(entries: [LogEntry], product: Product) {
        enqueue("log entries") { [self] in
            guard let hhID = householdID else { return }
            try await service.upsertProduct(
                CloudMap.newProduct(product, householdID: hhID,
                                    createdBy: service.currentUserID))
            try await service.insertLogEntries(entries.map {
                CloudMap.newEntry($0, householdID: hhID,
                                  loggedBy: service.currentUserID)
            })
        }
    }

    func didSaveProducts(_ products: [Product]) {
        enqueue("save fridge items") { [self] in
            guard let hhID = householdID else { return }
            for product in products {
                try await service.upsertProduct(
                    CloudMap.newProduct(product, householdID: hhID,
                                        createdBy: service.currentUserID))
            }
        }
    }

    func didDeleteProduct(_ id: UUID) {
        enqueue("delete fridge item") { [self] in
            try await service.deleteProduct(id: id)
        }
    }

    func didDeleteLogEntry(_ id: UUID) {
        enqueue("delete log entry") { [self] in
            try await service.deleteLogEntry(id: id)
        }
    }

    func didRenameUser(_ name: String) {
        enqueue("rename member") { [self] in
            try await service.updateMyMemberName(name)
        }
    }

    func didReset() {
        detach()
        chain = Task { [service] in try? await service.signOut() }
    }
}

#else

/// No-op stand-in so AppStore compiles identically without the Supabase SDK.
@MainActor
final class CloudSync {
    init(store: AppStore) {}
    func start() {}
    var isCloudBacked: Bool { false }
    func didCreateHousehold() {}
    func didJoinHousehold(code: String) {}
    func didAddDog(_ dog: Dog) {}
    func didLog(entries: [LogEntry], product: Product) {}
    func didSaveProducts(_ products: [Product]) {}
    func didDeleteProduct(_ id: UUID) {}
    func didDeleteLogEntry(_ id: UUID) {}
    func didRenameUser(_ name: String) {}
    func didReset() {}
}

#endif
