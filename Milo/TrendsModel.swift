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
        /// Spacing (in days) between chart x-axis labels for this range.
        var axisStride: Int {
            switch self {
            case .week:    return 1
            case .month:   return 5
            case .quarter: return 15
            }
        }
        /// x-axis label format: weekday initials for a week, day/month otherwise.
        var axisLabel: Date.FormatStyle {
            self == .week ? .dateTime.weekday(.narrow) : .dateTime.day().month(.narrow)
        }
    }

    // MARK: Guideline constants — single source of truth for text AND logic

    /// Vet rule-of-thumb: treats/extras should stay under this share of a dog's
    /// daily calories. Drives the guideline line, the copy, and the digest — so
    /// the number can never disagree with itself across the UI.
    static let treatGuidelinePct = 10
    /// Distinct logged days required before Trends shows charts instead of the
    /// "few days of logging" empty state.
    static let minDaysForTrends = 3

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
        // Trends is a record of COMPLETED days only — today (in progress) lives on
        // the dog's dashboard rings, not here — so the window ends yesterday.
        let lastDay = cal.date(byAdding: .day, value: -1, to: today) ?? today

        // Build empty buckets for every completed day in the range, oldest first.
        var buckets: [Date: Day] = [:]
        var ordered: [Date] = []
        for offset in stride(from: range.days - 1, through: 0, by: -1) {
            guard let d = cal.date(byAdding: .day, value: -offset, to: lastDay) else { continue }
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

        // Feeder split over the range's completed days (today excluded via the set).
        let dayset = Set(ordered)
        let inRange = mine.filter { dayset.contains(cal.startOfDay(for: $0.time)) }
        var byMember: [UUID: (member: Member, count: Int)] = [:]
        for e in inRange {
            let existing = byMember[e.loggedBy.id]
            byMember[e.loggedBy.id] = (e.loggedBy, (existing?.count ?? 0) + 1)
        }
        let totalEntries = inRange.count
        let ranked = byMember.values.sorted { $0.count > $1.count }
        // Largest-remainder rounding so the shares always sum to exactly 100%
        // (independent rounding can give 99% or 101% with 3+ feeders).
        let pcts = Self.wholePercentages(ranked.map(\.count))
        self.feeders = zip(ranked, pcts).map {
            FeederShare(member: $0.0.member, count: $0.0.count, percent: $0.1)
        }

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

    /// Completed days in the range that have data — a gap isn't "ate nothing".
    /// (The window already excludes today, so every day here is finished.)
    private var loggedDaysInRange: [Day] { days.filter(\.hasData) }

    /// The last 7 completed days that have data — the "this week" window.
    private var thisWeek: [Day] { Array(loggedDaysInRange.suffix(7)) }

    /// "Averaged N% of target this week" — mean of each completed day's kcal ÷
    /// target, over the last 7 finished days. nil when there's nothing to average
    /// yet (e.g. only today is logged).
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

    /// Average treats-% across the range's completed days.
    var avgTreatPercent: Int {
        let logged = loggedDaysInRange
        guard !logged.isEmpty else { return 0 }
        return Int((logged.reduce(0.0) { $0 + Double($1.treatPercent) } / Double(logged.count)).rounded())
    }

    /// Whole-number percentages that sum to exactly 100 (largest-remainder).
    static func wholePercentages(_ counts: [Int]) -> [Int] {
        let total = counts.reduce(0, +)
        guard total > 0 else { return counts.map { _ in 0 } }
        let exact = counts.map { Double($0) / Double(total) * 100 }
        var floors = exact.map { Int($0) }
        var leftover = 100 - floors.reduce(0, +)
        // Hand the leftover points to the largest fractional remainders first.
        for i in exact.enumerated()
            .sorted(by: { ($0.element - Double(Int($0.element))) > ($1.element - Double(Int($1.element))) })
            .map(\.offset) where leftover > 0 {
            floors[i] += 1
            leftover -= 1
        }
        return floors
    }

    /// The upper bound for the calorie chart's y-axis — a little headroom above
    /// the taller of the target line and the biggest day.
    var kcalAxisMax: Int {
        let peak = max(target, days.map(\.kcal).max() ?? 0)
        return Int((Double(peak) * 1.15 / 50).rounded(.up)) * 50
    }

    /// Fewer than ~3 days of history → the screen shows a friendly empty state
    /// instead of near-meaningless charts.
    var hasEnoughData: Bool { totalLoggedDays >= Self.minDaysForTrends }

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
        s.append(("treatGuideline", "\(Self.treatGuidelinePct)% (aim to stay under)"))
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
