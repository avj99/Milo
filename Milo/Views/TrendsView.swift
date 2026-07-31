import SwiftUI
import Charts

/// Trends (v1) — the story the log tells over time, per dog. Everything here is
/// read-only: it aggregates the FULL history via `TrendsModel` (deterministic
/// Swift; the dashboard's daily helpers are today-only by design) and renders it
/// in the app's card language. Non-medical framing throughout — every number is
/// an estimate, never a prescription.
struct TrendsView: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedDogID: UUID?
    @State private var range: TrendsModel.Range = .week
    @State private var digest: String?
    @State private var digestState: DigestState = .idle

    enum DigestState { case idle, loading, ready, unavailable }

    /// The dog in focus — the explicit selection, else the first dog.
    private var dog: Dog? {
        if let id = selectedDogID, let d = store.dog(id) { return d }
        return store.dogs.first
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let dog {
                content(for: dog)
            } else {
                noDogState
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .task(id: dog?.id) { await loadDigest() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Trends").font(.milo(22, .heavy)).foregroundStyle(Theme.ink)
                Text(dog == nil ? "How eating changes over time"
                                : "How \(dog!.name)'s eating changes over time")
                    .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Theme.bg)
    }

    // MARK: Content

    @ViewBuilder
    private func content(for dog: Dog) -> some View {
        let model = TrendsModel(log: store.log, dog: dog, range: range)
        // "This week" stats are anchored to a literal 7-day window so the
        // headline and adequacy chips stay stable as the chart range changes.
        let week = TrendsModel(log: store.log, dog: dog, range: .week)

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    if store.dogs.count > 1 { dogSwitcher }

                    if model.hasEnoughData {
                        rangePicker
                        CaloriesCard(model: model, week: week)
                        TreatCreepCard(model: model)
                        NutritionAdequacyCard(week: week)
                        HStack(spacing: 14) {
                            StreakCard(streak: model.streak)
                            FeedersCard(feeders: model.feeders)
                        }
                        digestCard(week: week)
                        WeightPlaceholderCard().id("bottom")
                    } else {
                        emptyState(model: model)
                        WeightPlaceholderCard().id("bottom")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 130)
            }
            .onAppear { debugScroll(proxy) }
        }
    }

    /// DEBUG-only: jump to the bottom card so verification screenshots can
    /// capture the lower sections (no interaction tooling on the simulator).
    /// Mirrors the MILO_SCREEN launch hooks; no effect in release builds.
    private func debugScroll(_ proxy: ScrollViewProxy) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["MILO_TRENDS_SCROLL"] == "bottom" else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        #endif
    }

    // MARK: Dog switcher

    private var dogSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 9) {
                ForEach(store.dogs) { d in
                    let on = d.id == dog?.id
                    Button {
                        selectedDogID = d.id
                        digest = nil; digestState = .idle
                    } label: {
                        HStack(spacing: 7) {
                            Text(d.emoji).font(.system(size: 15))
                            Text(d.name).font(.milo(13, .heavy))
                        }
                        .foregroundStyle(on ? .white : Theme.ink)
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .background(on ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.card))
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: on ? 0 : 1))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: Range picker

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(TrendsModel.Range.allCases) { r in
                let on = r == range
                Button { withAnimation(.easeOut(duration: 0.2)) { range = r } } label: {
                    Text(r.label)
                        .font(.milo(13, .heavy))
                        .foregroundStyle(on ? .white : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(on ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.clear))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(4)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    // MARK: Weekly digest card (hidden entirely unless the model produced text)

    @ViewBuilder
    private func digestCard(week: TrendsModel) -> some View {
        if digestState == .ready, let digest, !digest.isEmpty {
            TrendCard(title: "Milo's weekly note", trailing: "on-device AI") {
                HStack(alignment: .top, spacing: 11) {
                    Text("✨").font(.system(size: 20))
                    Text(digest)
                        .font(.milo(13, .semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Empty + no-dog states

    private func emptyState(model: TrendsModel) -> some View {
        VStack(spacing: 12) {
            Text("🐾").font(.system(size: 52))
            Text("Trends appear after a few days of logging")
                .font(.milo(16, .heavy)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text("Keep logging \(dog?.name ?? "your dog")'s meals and treats. In a few days you'll see calories vs target, treat creep, nutrition and who's been feeding.")
                .font(.milo(13, .semibold)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("\(model.totalLoggedDays) of 3 days logged so far")
                .font(.milo(11.5, .heavy)).foregroundStyle(Theme.brand)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.okChipBg).clipShape(Capsule())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36).padding(.horizontal, 12)
        .miloCard(radius: Theme.rCard, padding: 0)
        .padding(.top, 8)
    }

    private var noDogState: some View {
        VStack(spacing: 12) {
            Text("📈").font(.system(size: 52))
            Text("No dogs yet").font(.milo(17, .heavy)).foregroundStyle(Theme.ink)
            Text("Add a dog and start logging to see trends here.")
                .font(.milo(13, .semibold)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center).padding(.horizontal, 44)
        }
    }

    // MARK: Digest loading (availability-gated; deterministic tools ground it)

    private func loadDigest() async {
        guard let dog else { digestState = .unavailable; return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleAI.isAvailable {
            digestState = .loading
            let week = TrendsModel(log: store.log, dog: dog, range: .week)
            guard week.hasEnoughData else { digestState = .unavailable; return }
            if let text = try? await AppleAI.weeklyDigest(model: week), !text.isEmpty {
                digest = text
                digestState = .ready
            } else {
                digestState = .unavailable
            }
            return
        }
        #endif
        digestState = .unavailable
    }
}

// MARK: - Card container (matches the dashboard's card header style)

private struct TrendCard<Content: View>: View {
    var title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title.uppercased()).font(.milo(11, .heavy)).foregroundStyle(Theme.muted)
                Spacer()
                if let trailing {
                    Text(trailing).font(.milo(9.5, .bold)).foregroundStyle(Theme.muted.opacity(0.8))
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .miloCard(radius: 20, padding: 0)
    }
}

// MARK: - 1. Calories vs target

private struct CaloriesCard: View {
    let model: TrendsModel
    let week: TrendsModel

    var body: some View {
        TrendCard(title: "Calories vs target", trailing: "target \(model.target) kcal") {
            VStack(alignment: .leading, spacing: 12) {
                headline
                chart
                legend
            }
        }
    }

    private var headline: some View {
        Group {
            if let pct = week.avgPercentOfTargetThisWeek {
                let over = pct > 110
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(pct)%")
                        .font(.milo(30, .heavy))
                        .foregroundStyle(over ? Theme.accentDeep : Theme.brandDeep)
                    Text("of target, on average this week")
                        .font(.milo(12.5, .bold)).foregroundStyle(Theme.muted)
                }
            } else {
                Text("Not enough logged days this week yet")
                    .font(.milo(13, .bold)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Target", model.target))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .foregroundStyle(Theme.muted.opacity(0.55))
            ForEach(model.days) { day in
                if day.kcal > 0 {
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("kcal", day.kcal))
                        .foregroundStyle(day.kcal > model.target ? Theme.accent : Theme.brand)
                        .cornerRadius(3)
                }
            }
        }
        .chartYScale(domain: 0...model.kcalAxisMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel().font(.milo(9, .bold)).foregroundStyle(Theme.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xStride)) { value in
                AxisValueLabel(format: xFormat)
                    .font(.milo(9, .bold)).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 172)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(Theme.brand, "On / under target")
            legendDot(Theme.accent, "Over target")
            Spacer()
        }
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.milo(10, .bold)).foregroundStyle(Theme.muted)
        }
    }

    private var xStride: Int {
        switch model.range { case .week: return 1; case .month: return 5; case .quarter: return 15 }
    }
    private var xFormat: Date.FormatStyle {
        model.range == .week ? .dateTime.weekday(.narrow) : .dateTime.day().month(.narrow)
    }
}

// MARK: - 2. Treat creep

private struct TreatCreepCard: View {
    let model: TrendsModel

    private var yMax: Int { max(20, (model.days.map(\.treatPercent).max() ?? 0) + 4) }

    var body: some View {
        TrendCard(title: "Treat creep", trailing: "avg \(model.avgTreatPercent)%") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Share of daily calories from treats & extras, against the 10% guideline.")
                    .font(.milo(11.5, .semibold)).foregroundStyle(Theme.muted)
                chart
            }
        }
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("Guideline", 10))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .foregroundStyle(Theme.accentDeep.opacity(0.55))
                .annotation(position: .top, alignment: .trailing) {
                    Text("10% guide").font(.milo(9, .heavy)).foregroundStyle(Theme.accentDeep)
                }
            ForEach(model.days.filter(\.hasData)) { day in
                LineMark(x: .value("Day", day.date, unit: .day),
                         y: .value("Treats %", day.treatPercent))
                    .foregroundStyle(Theme.brand)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                PointMark(x: .value("Day", day.date, unit: .day),
                          y: .value("Treats %", day.treatPercent))
                    .symbolSize(28)
                    .foregroundStyle(day.treatPercent > 10 ? Theme.accent : Theme.brand)
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel(format: Decimal.FormatStyle.Percent.percent.scale(1))
                    .font(.milo(9, .bold)).foregroundStyle(Theme.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xStride)) { _ in
                AxisValueLabel(format: xFormat)
                    .font(.milo(9, .bold)).foregroundStyle(Theme.muted)
            }
        }
        .frame(height: 150)
    }

    private var xStride: Int {
        switch model.range { case .week: return 1; case .month: return 5; case .quarter: return 15 }
    }
    private var xFormat: Date.FormatStyle {
        model.range == .week ? .dateTime.weekday(.narrow) : .dateTime.day().month(.narrow)
    }
}

// MARK: - 3. Nutrition adequacy (quiet chips; prominent only when under)

private struct NutritionAdequacyCard: View {
    let week: TrendsModel

    var body: some View {
        TrendCard(title: "Nutrition adequacy", trailing: "weekly avg vs AAFCO") {
            VStack(spacing: 10) {
                row(name: "Protein", avg: week.avgProteinGThisWeek, target: week.proteinTargetG)
                row(name: "Fat", avg: week.avgFatGThisWeek, target: week.fatTargetG)
            }
        }
    }

    private func row(name: String, avg: Int, target: Int) -> some View {
        let met = avg >= target
        return HStack(spacing: 10) {
            Text(name).font(.milo(13.5, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
            Text("\(avg)g avg · \(target)g target")
                .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
            Chip(text: met ? "Met" : "Below target",
                 icon: met ? nil : "⚠",
                 kind: met ? .ok : .soft)
        }
    }
}

// MARK: - 4. Logging streak

private struct StreakCard: View {
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STREAK").font(.milo(11, .heavy)).foregroundStyle(Theme.muted)
            Text("🐾 \(streak)")
                .font(.milo(30, .heavy)).foregroundStyle(Theme.brandDeep)
            Text(streak == 0 ? "Log today to start one"
                             : (streak == 1 ? "day logged" : "days in a row"))
                .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .miloCard(radius: 20, padding: 0)
    }
}

// MARK: - 5. Who's feeding

private struct FeedersCard: View {
    let feeders: [TrendsModel.FeederShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO'S FEEDING").font(.milo(11, .heavy)).foregroundStyle(Theme.muted)
            if feeders.isEmpty {
                Text("No entries in range").font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                    .padding(.top, 6)
            } else {
                ForEach(feeders.prefix(4)) { f in
                    HStack(spacing: 8) {
                        Text(f.member.initials)
                            .font(.milo(10, .heavy)).foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(f.member.palette.gradient)
                            .clipShape(Circle())
                        Text(f.member.name).font(.milo(12, .heavy)).foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(f.percent)%").font(.milo(12, .heavy)).foregroundStyle(Theme.brand)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .miloCard(radius: 20, padding: 0)
    }
}

// MARK: - 8. Weight over time (placeholder — weight tracking isn't built yet)

private struct WeightPlaceholderCard: View {
    var body: some View {
        ZStack {
            // A faint faux-trend line so the card reads as a chart-to-come.
            GeometryReader { geo in
                Path { p in
                    let pts: [CGFloat] = [0.7, 0.55, 0.62, 0.4, 0.45, 0.3, 0.34]
                    let stepX = geo.size.width / CGFloat(pts.count - 1)
                    for (i, v) in pts.enumerated() {
                        let pt = CGPoint(x: CGFloat(i) * stepX, y: geo.size.height * v)
                        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                    }
                }
                .stroke(Theme.brand.opacity(0.18),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            VStack(spacing: 8) {
                Text("⚖️").font(.system(size: 30))
                Text("Weight over time").font(.milo(15, .heavy)).foregroundStyle(Theme.ink)
                Text("Coming soon")
                    .font(.milo(10.5, .heavy)).foregroundStyle(Theme.accentDeep)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.accentSoft).clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .padding(16)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }
}
