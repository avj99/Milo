import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: AppStore
    var dogID: UUID
    @Binding var path: [Route]
    @Environment(\.dismiss) private var dismiss

    private var dog: Dog? { store.dog(dogID) }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let dog {
                ScrollView {
                    VStack(spacing: 0) {
                        if let activity = store.latestActivity(for: dogID) {
                            ActivityStrip(entry: activity, dogName: dog.name)
                                .padding(.bottom, 4)
                        }
                        CalorieRing(dog: dog)
                        statRow(dog: dog)
                        todaySection(dog: dog)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 120)
                }
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            BackButton { dismiss() }
            VStack(alignment: .leading, spacing: 1) {
                Text(dog?.name ?? "")
                    .font(.milo(19, .heavy)).foregroundStyle(Theme.ink)
                Text("\(dog?.breed ?? "") · \(Int(dog?.weightKg ?? 0)) kg · \(dog?.lifeStage.short ?? "")")
                    .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button { path.append(.household) } label: {
                MemberStack(members: store.members.filter { !$0.isYou } + [store.currentMember])
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Theme.bg)
    }

    // MARK: Real stat cards (replace the mockup's macro estimates with honest numbers)

    private func statRow(dog: Dog) -> some View {
        HStack(spacing: 10) {
            statCard(value: "\(dog.dailyTarget)", label: "Target", note: "kcal / day")
            statCard(value: "\(store.consumed(for: dogID))", label: "Eaten", note: "so far today")
            statCard(value: "\(store.treatPercent(for: dogID))%", label: "Treats", note: "aim < 10%")
        }
        .padding(.top, 16)
    }

    private func statCard(value: String, label: String, note: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.milo(17, .heavy)).foregroundStyle(Theme.brandDeep)
            Text(label.uppercased()).font(.milo(10.5, .heavy)).foregroundStyle(Theme.muted)
            Text(note).font(.milo(9.5, .bold)).foregroundStyle(Theme.muted.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .miloCard(radius: 18, padding: 0)
    }

    private func todaySection(dog: Dog) -> some View {
        VStack(spacing: 0) {
            SectionHeader(title: "Today") {
                Text("Treats \(store.treatPercent(for: dogID))% · aim <10%")
                    .font(.milo(11.5, .heavy))
                    .foregroundStyle(Theme.alert)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Theme.alertSoft)
                    .clipShape(Capsule())
            }
            .padding(.vertical, 20)

            ForEach(store.entries(for: dogID)) { entry in
                LogRow(entry: entry)
            }
        }
    }
}

// MARK: - Big calorie ring

struct CalorieRing: View {
    @EnvironmentObject var store: AppStore
    var dog: Dog

    var body: some View {
        let remaining = store.remaining(for: dog)
        let over = remaining < 0
        VStack(spacing: 0) {
            ZStack {
                ProgressRing(progress: store.progress(for: dog), lineWidth: 18, over: over)
                VStack(spacing: 0) {
                    Text("\(abs(remaining))")
                        .font(.milo(46, .heavy))
                        .foregroundStyle(over ? Theme.alert : Theme.brandDeep)
                    Text(over ? "KCAL OVER" : "KCAL LEFT")
                        .font(.milo(12.5, .heavy)).foregroundStyle(Theme.muted)
                        .padding(.top, 5)
                    (Text("\(store.consumed(for: dog.id)) of ")
                        .foregroundStyle(Theme.muted)
                     + Text("\(dog.dailyTarget)").foregroundStyle(Theme.ink).bold()
                     + Text(" today").foregroundStyle(Theme.muted))
                        .font(.milo(12.5, .semibold))
                        .padding(.top, 8)
                }
            }
            .frame(width: 216, height: 216)
            .padding(.top, 6)

            Text(CalorieEngine.result(for: dog).caveats.first
                 ?? "Target is an estimate — adjust with your vet.")
                .font(.milo(11, .semibold))
                .foregroundStyle(dog.isGrowing ? Theme.accentDeep : Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 30)
        }
    }
}

// MARK: - Live activity strip

struct ActivityStrip: View {
    var entry: LogEntry
    var dogName: String

    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: entry.time)
    }

    var body: some View {
        HStack(spacing: 11) {
            Text(entry.loggedBy.initials)
                .font(.milo(13, .heavy)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(entry.loggedBy.palette.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                (Text("\(entry.loggedBy.name) fed \(dogName) ")
                    .foregroundStyle(Theme.ink)
                 + Text(entry.product.name.lowercased()).foregroundStyle(Theme.ink).bold())
                    .font(.milo(13, .semibold))
                Text("\(timeText) · \(entry.portionText) · \(entry.kcal) kcal")
                    .font(.milo(11, .bold)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Circle().fill(Theme.brand).frame(width: 6, height: 6)
                Text("Live").font(.milo(9.5, .heavy))
            }
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(hex: 0xDCF0E4))
            .clipShape(Capsule())
        }
        .padding(13)
        .background(
            LinearGradient(colors: [Color(hex: 0xF4FAF6), Color(hex: 0xEAF3EC)],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - Log row

struct LogRow: View {
    var entry: LogEntry
    var justAdded: Bool = false

    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: entry.time)
    }

    var body: some View {
        HStack(spacing: 13) {
            Text(entry.product.emoji)
                .font(.system(size: 21))
                .frame(width: 42, height: 42)
                .background(Theme.track)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.product.name).font(.milo(14.5, .heavy)).foregroundStyle(Theme.ink)
                    if justAdded {
                        Text("NEW").font(.milo(9, .heavy))
                            .foregroundStyle(Theme.brandDeep)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                detailLine
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0) {
                Text(entry.product.isEstimate ? "~\(entry.kcal)" : "\(entry.kcal)")
                    .font(.milo(15, .heavy)).foregroundStyle(Theme.brandDeep)
                Text("KCAL").font(.milo(9.5, .heavy)).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(justAdded ? Color(hex: 0xFEF9EF) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.rRow, style: .continuous)
            .strokeBorder(justAdded ? Theme.accent : Theme.line, lineWidth: 1))
        .padding(.bottom, 10)
    }

    private var detailLine: some View {
        var parts: [String] = [timeText, entry.portionText]
        if entry.product.isEstimate { parts.append("~est") }
        if entry.flaggedAllergen { parts.append("⚠ allergen") }
        let prefix = parts.joined(separator: " · ")
        return (Text("\(prefix) · ")
                    .foregroundStyle(Theme.muted)
                + Text(entry.loggedBy.name).foregroundStyle(Theme.brand).bold())
            .font(.milo(11.5, .bold))
    }
}
