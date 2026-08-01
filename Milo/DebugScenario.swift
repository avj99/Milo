import Foundation

#if DEBUG
// A scripted, synthetic end-to-end scenario for verifying that the whole flow
// hangs together: a food added to My Fridge → logged to a dog's meal → shows up
// on the Dashboard (ring, treats %, nutrient rings, today's log) → and rolls
// into Trends (bars, treat creep, streak, who's feeding).
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

        // MARK: Dog
        let dog = Dog(
            name: "Milo", emoji: "🐕", avatar: [0xF6C86B, 0xD98A1F],
            breed: "Labrador Retriever", ageMonths: 36,
            weightKg: 30, idealWeightKg: 30,
            bodyCondition: .ideal, lifeStage: .neuteredAdult,
            allergens: [], targetOverride: 1450)
        store.addOnboardedDog(dog)

        // MARK: Two foods, added to My Fridge (the real path)
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

        // MARK: Backdated history (days −9…−1) so Trends has depth.
        // Mom does breakfast, You does dinner; dinner size alternates so bars
        // land both under and over target; a treat spike every third day.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func time(_ dayOffset: Int, hour: Int) -> Date {
            let day = cal.date(byAdding: .day, value: -dayOffset, to: today) ?? today
            return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        func entry(_ p: Product, _ portion: Int, _ when: Date, by who: Member) -> LogEntry {
            LogEntry(dogID: dog.id, product: p, portionCount: portion, time: when,
                     loggedBy: who, kcal: p.kcalPerUnit * portion, flaggedAllergen: false)
        }
        var history: [LogEntry] = []
        for off in 1...9 {
            let dinnerCups = off.isMultiple(of: 2) ? 3 : 2      // 1750 (over) vs 1400 (under)
            history.append(entry(kibble, 2, time(off, hour: 8),  by: mom))
            history.append(entry(kibble, dinnerCups, time(off, hour: 18), by: you))
            if off.isMultiple(of: 3) {
                history.append(entry(treat, 2, time(off, hour: 15), by: mom))
            }
        }
        store.log.append(contentsOf: history)

        // MARK: Today's meal — logged through the SAME method the Assign UI uses.
        // Kibble 2 cups (700 kcal) + one treat (60 kcal) = 760 kcal today.
        store.logProduct(kibble, to: [(dog: dog, portionCount: 2)], by: you)
        store.logProduct(treat,  to: [(dog: dog, portionCount: 1)], by: you)
    }
}
#endif
