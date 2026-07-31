import Foundation

// MARK: - Trends aggregation
//
// The Trends screen needs the OPPOSITE of the dashboard's daily math. The store's
// consumed()/entries() helpers are TODAY-only by design — the calorie ring and
// nutrient rings are per-day targets that must reset at midnight. Trends instead
// reads the FULL log history for a dog and buckets it by calendar day.
//
// Everything here is deterministic Swift. No AI touches these numbers — the
// optional weekly digest only restates stats computed here (see AppleAI).

struct TrendsModel {

    /// The range the picker offers. Days are inclusive of today.
    enum Range: String, CaseIterable, Identifiable {
        case week, month, quarter
        var id: String { rawValue }
        var label: String {
            switch self {
            case .week:    return "7D"
            case .month:   return "30D"
            case .quarter: return "3M"
            }
        }
        var days: Int {
            switch self {
            case .week:    return 7
            case .month:   return 30
            case .quarter: return 90
            }
        }
    }

    /// One calendar day of intake for the selected dog.
    struct Day: Identifiable {
        let date: Date          // start of the day
        var kcal: Int
        var treatKcal: Int      // calories from anything that isn't kibble/wet
        var proteinG: Double
        var fatG: Double
        var entryCount: Int
        var id: Date { date }

        /// Share of the day's calories that came from treats/extras — same rule
        /// as Store.treatPercent (everything that isn't a planned meal).
        var treatPercent: Int {
            guard kcal > 0 else { return 0 }
            return Int((Double(treatKcal) / Double(kcal) * 100).rounded())
        }
        var hasData: Bool { entryCount > 0 }
    }

    /// Household member's share of the logging for the range.
    struct FeederShare: Identifiable {
        let member: Member
        let count: Int
        let percent: Int
        var id: UUID { member.id }
    }

    // Inputs
    let dog: Dog
    let range: Range

    /// One `Day` per calendar day in the range, oldest → newest. Days with no
    /// entries are present with zeros so the chart shows the gap honestly.
    let days: [Day]
    /// The feeding split over the range (entries per member), largest first.
    let feeders: [FeederShare]
    /// Consecutive days (ending today, or yesterday if today isn't logged yet)
    /// with at least one entry — computed over the FULL history, not the range.
    let streak: Int
    /// Distinct days in all of history with at least one entry for this dog.
    /// Drives the "not enough data yet" empty state.
    let totalLoggedDays: Int

    private let calendar: Calendar

    // MARK: Init

    /// - Parameters:
    ///   - log: the full, unfiltered log (all dogs, all history).
    ///   - dog: the dog to aggregate for.
    ///   - range: the selected window.
    ///   - now: injected for testability; defaults to the current instant.
    init(log: [LogEntry], dog: Dog, range: Range, now: Date = Date()) {
        var cal = Calendar.current
        cal.timeZone = .current
        self.calendar = cal
        self.dog = dog
        self.range = range

        let mine = log.filter { $0.dogID == dog.id }
        let today = cal.startOfDay(for: now)

        // Build empty buckets for every day in the range, oldest first.
        var buckets: [Date: Day] = [:]
        var ordered: [Date] = []
        for offset in stride(from: range.days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            buckets[d] = Day(date: d, kcal: 0, treatKcal: 0, proteinG: 0, fatG: 0, entryCount: 0)
            ordered.append(d)
        }

        // Fold entries into their day bucket (only those inside the range).
        for e in mine {
            let day = cal.startOfDay(for: e.time)
            guard var bucket = buckets[day] else { continue }
            bucket.kcal += e.kcal
            if !e.product.category.isMainMeal { bucket.treatKcal += e.kcal }
            bucket.proteinG += (e.product.proteinGPerUnit ?? 0) * Double(e.portionCount)
            bucket.fatG += (e.product.fatGPerUnit ?? 0) * Double(e.portionCount)
            bucket.entryCount += 1
            buckets[day] = bucket
        }
        self.days = ordered.compactMap { buckets[$0] }

        // Feeder split over the range.
        let rangeStart = ordered.first ?? today
        let inRange = mine.filter { cal.startOfDay(for: $0.time) >= rangeStart }
        var byMember: [UUID: (member: Member, count: Int)] = [:]
        for e in inRange {
            let existing = byMember[e.loggedBy.id]
            byMember[e.loggedBy.id] = (e.loggedBy, (existing?.count ?? 0) + 1)
        }
        let totalEntries = inRange.count
        self.feeders = byMember.values
            .map { FeederShare(member: $0.member, count: $0.count,
                               percent: totalEntries > 0
                                    ? Int((Double($0.count) / Double(totalEntries) * 100).rounded())
                                    : 0) }
            .sorted { $0.count > $1.count }

        // Streak + total logged days over the FULL history for this dog.
        let loggedDays = Set(mine.map { cal.startOfDay(for: $0.time) })
        self.totalLoggedDays = loggedDays.count

        var streakCount = 0
        // A day still in progress shouldn't "break" a streak: if today has no
        // entry yet, start counting from yesterday.
        var cursor = loggedDays.contains(today)
            ? today
            : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        while loggedDays.contains(cursor) {
            streakCount += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        self.streak = streakCount
    }

    // MARK: Derived headline stats

    var target: Int { dog.dailyTarget }

    /// Days in the range that actually have data (a gap isn't "ate nothing").
    private var loggedDaysInRange: [Day] { days.filter(\.hasData) }

    /// The last 7 calendar days of the range that have data — the "this week"
    /// window used for the headline and nutrition adequacy.
    private var thisWeek: [Day] { Array(loggedDaysInRange.suffix(7)) }

    /// "Averaged N% of target this week" — mean of each logged day's kcal ÷
    /// target, over the last 7 logged days. nil when there's nothing to average.
    var avgPercentOfTargetThisWeek: Int? {
        guard target > 0, !thisWeek.isEmpty else { return nil }
        let mean = thisWeek.reduce(0.0) { $0 + Double($1.kcal) / Double(target) } / Double(thisWeek.count)
        return Int((mean * 100).rounded())
    }

    /// Weekly average grams actually consumed, over logged days only.
    var avgProteinGThisWeek: Int {
        guard !thisWeek.isEmpty else { return 0 }
        return Int((thisWeek.reduce(0.0) { $0 + $1.proteinG } / Double(thisWeek.count)).rounded())
    }
    var avgFatGThisWeek: Int {
        guard !thisWeek.isEmpty else { return 0 }
        return Int((thisWeek.reduce(0.0) { $0 + $1.fatG } / Double(thisWeek.count)).rounded())
    }

    var proteinTargetG: Int { CalorieEngine.proteinTargetG(for: dog) }
    var fatTargetG: Int { CalorieEngine.fatTargetG(for: dog) }

    /// Average treats-% across logged days in the range.
    var avgTreatPercent: Int {
        let logged = loggedDaysInRange
        guard !logged.isEmpty else { return 0 }
        return Int((logged.reduce(0.0) { $0 + Double($1.treatPercent) } / Double(logged.count)).rounded())
    }

    /// The upper bound for the calorie chart's y-axis — a little headroom above
    /// the taller of the target line and the biggest day.
    var kcalAxisMax: Int {
        let peak = max(target, days.map(\.kcal).max() ?? 0)
        return Int((Double(peak) * 1.15 / 50).rounded(.up)) * 50
    }

    /// Fewer than ~3 days of history → the screen shows a friendly empty state
    /// instead of near-meaningless charts.
    var hasEnoughData: Bool { totalLoggedDays >= 3 }

    // MARK: Digest source (words come from the model; every number is from here)

    /// Keyed, preformatted statistics the on-device digest model retrieves via
    /// its getTrendStat tool (see AppleAI.TrendsStatsTool). Every value is a
    /// finished string with units, computed here in deterministic Swift — the
    /// model never recomputes or invents a figure, it only fetches and phrases.
    /// Ordered so the tool's "list" response reads sensibly.
    func digestStatMap() -> [(key: String, value: String)] {
        var s: [(String, String)] = []
        s.append(("dogName", dog.name))
        s.append(("breed", dog.breed))
        s.append(("calorieTarget", "\(target) kcal per day"))
        s.append(("avgPercentOfTarget", avgPercentOfTargetThisWeek.map { "\($0)%" } ?? "not enough data"))
        s.append(("avgTreatPercent", "\(avgTreatPercent)%"))
        s.append(("treatGuideline", "10% (aim to stay under)"))
        s.append(("avgProtein", "\(avgProteinGThisWeek) g per day"))
        s.append(("proteinTarget", "\(proteinTargetG) g per day"))
        s.append(("avgFat", "\(avgFatGThisWeek) g per day"))
        s.append(("fatTarget", "\(fatTargetG) g per day"))
        s.append(("loggingStreak", "\(streak) days in a row"))
        s.append(("daysLoggedThisWeek", "\(days.filter(\.hasData).suffix(7).count) of the last 7 days"))
        if let top = feeders.first {
            s.append(("topFeeder", "\(top.member.name) logged \(top.percent)% of entries"))
        }
        return s
    }
}
