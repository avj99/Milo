import Foundation

#if DEBUG
// A scripted, synthetic end-to-end scenario for verifying that the whole flow
// hangs together: a food added to My Fridge → logged to a dog's meal → shows up
// on the Dashboard (ring, treats %, nutrient rings, today's log) → and rolls
// into Trends (bars, treat creep, streak, who's feeding).
//
// Seeds TWO dogs in one household (Milo + Luna) so the Trends dog switcher —
// which only appears with 2+ dogs — can be exercised; each dog has its own
// target, history, and feeder mix so switching visibly changes the numbers.
//
// It drives the REAL store methods the UI calls (`addToFridge`, `logProduct`),
// not a hand-built JSON snapshot, so the code paths under test are the real
// ones. Backdated history (which `logProduct` can't create — it always logs
// "now") is appended directly so Trends has multiple days to chart.
//
// Triggered only in DEBUG via the launch env `MILO_SCENARIO=demo`
// (`SIMCTL_CHILD_MILO_SCENARIO=demo`); no effect in release or normal use.
enum DebugScenario {

    @MainActor
    static func seedDemo(_ store: AppStore) {
        store.resetAll()                       // clean slate every launch

        // MARK: Household + members (You + Mom)
        let you = store.currentMember          // the fresh "You" from resetAll
        let mom = Member(name: "Mom", initials: "M", palette: .mom)
        store.members = [you, mom]
        store.createHousehold(name: "The Barkers")   // household adopts both members

        // MARK: Two dogs
        let milo = Dog(
            name: "Milo", emoji: "🐕", avatar: [0xF6C86B, 0xD98A1F],
            breed: "Labrador Retriever", ageMonths: 36,
            weightKg: 30, idealWeightKg: 30,
            bodyCondition: .ideal, lifeStage: .neuteredAdult,
            allergens: [], targetOverride: 1450)
        let luna = Dog(
            name: "Luna", emoji: "🐩", avatar: [0xE9885E, 0xDB5A4B],
            breed: "Border Collie", ageMonths: 48,
            weightKg: 16, idealWeightKg: 16,
            bodyCondition: .ideal, lifeStage: .active,
            allergens: [], targetOverride: 900)
        store.addOnboardedDog(milo)
        store.addOnboardedDog(luna)

        // MARK: Foods, added to My Fridge (household-wide, the real path)
        let kibble = Product(
            name: "Salmon Kibble", brand: "Acme", emoji: "🥣",
            category: .kibble, kcalPerUnit: 350, portionBasis: "cup",
            ingredients: ["salmon", "rice", "pea"],
            proteinGPerUnit: 17, fatGPerUnit: 4, fiberGPerUnit: 1, moistureGPerUnit: 1.5)
        let treat = Product(
            name: "PB Biscuit", brand: "Chewy", emoji: "🦴",
            category: .treat, kcalPerUnit: 60, portionBasis: "piece",
            ingredients: ["peanut", "wheat"],
            proteinGPerUnit: 1.5, fatGPerUnit: 2, fiberGPerUnit: 0.3, moistureGPerUnit: 0.2)
        store.addToFridge([kibble, treat])

        // MARK: Backdated history so Trends has depth (logProduct only logs "now").
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func time(_ dayOffset: Int, hour: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        func entry(_ p: Product, _ portion: Int, _ when: Date, by who: Member, for dogID: UUID) -> LogEntry {
            LogEntry(dogID: dogID, product: p, portionCount: portion, time: when,
                     loggedBy: who, kcal: p.kcalPerUnit * portion, flaggedAllergen: false)
        }
        var history: [LogEntry] = []

        // Milo: Mom does breakfast, You does dinner; dinner size alternates so
        // bars land both under and over his 1450 target; treat spike every 3rd day.
        for off in 1...9 {
            let dinnerCups = off.isMultiple(of: 2) ? 3 : 2      // 1750 (over) vs 1400 (under)
            history.append(entry(kibble, 2, time(off, hour: 8),  by: mom, for: milo.id))
            history.append(entry(kibble, dinnerCups, time(off, hour: 18), by: you, for: milo.id))
            if off.isMultiple(of: 3) {
                history.append(entry(treat, 2, time(off, hour: 15), by: mom, for: milo.id))
            }
        }

        // Luna: smaller dog (900 target), mostly on-target, You feeds most of the
        // time — a deliberately different profile so switching dogs shows a change.
        for off in 1...8 {
            let dinnerCups = off.isMultiple(of: 4) ? 2 : 1      // 1050 (over) vs 700 (under)
            history.append(entry(kibble, 1, time(off, hour: 7), by: you, for: luna.id))
            history.append(entry(kibble, dinnerCups, time(off, hour: 19),
                                 by: off.isMultiple(of: 3) ? mom : you, for: luna.id))
            if off.isMultiple(of: 5) {
                history.append(entry(treat, 1, time(off, hour: 16), by: you, for: luna.id))
            }
        }
        store.log.append(contentsOf: history)

        // MARK: Today's meals — logged through the SAME method the Assign UI uses.
        store.logProduct(kibble, to: [(dog: milo, portionCount: 2)], by: you)   // 700
        store.logProduct(treat,  to: [(dog: milo, portionCount: 1)], by: you)   // 60
        store.logProduct(kibble, to: [(dog: luna, portionCount: 1)], by: you)   // 350
    }
}
#endif
