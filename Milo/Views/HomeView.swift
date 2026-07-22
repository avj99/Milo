import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: AppStore
    @Binding var path: [Route]

    private var dateLine: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: Date())
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    ForEach(store.dogs) { dog in
                        DogCard(dog: dog)
                            .onTapGesture { path.append(.dashboard(dog.id)) }
                    }
                    Text("Tap a dog to open their dashboard")
                        .font(.milo(12.5, .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 22)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(store.household?.name ?? "Your household") · \(dateLine)".uppercased())
                    .font(.milo(12, .heavy))
                    .foregroundStyle(Theme.muted)
                Text("Good morning 🐾")
                    .font(.milo(27, .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { path.append(.household) } label: {
                MemberStack(members: store.members.filter { !$0.isYou } + [store.currentMember])
            }
            .buttonStyle(PressStyle())
            .padding(.top, 6)
        }
        .padding(.top, 8)
        .padding(.bottom, 14)
    }
}

// MARK: - Dog card

struct DogCard: View {
    @EnvironmentObject var store: AppStore
    var dog: Dog

    var body: some View {
        HStack(spacing: 15) {
            Text(dog.emoji)
                .font(.system(size: 30))
                .frame(width: 58, height: 58)
                .background(dog.avatarGradient)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text(dog.name).font(.milo(18, .heavy)).foregroundStyle(Theme.ink)
                    allergyChip
                }
                Text(dog.subtitle)
                    .font(.milo(12.5, .bold)).foregroundStyle(Theme.muted)

                HStack(spacing: 8) {
                    BudgetBar(progress: store.progress(for: dog),
                              over: store.remaining(for: dog) < 0)
                    Text("\(abs(store.remaining(for: dog))) \(store.remaining(for: dog) < 0 ? "over" : "left")")
                        .font(.milo(11.5, .heavy)).foregroundStyle(Theme.muted)
                        .fixedSize()
                }
                .padding(.top, 12)
            }

            MiniRing(progress: store.progress(for: dog))
        }
        .miloCard(radius: Theme.rCard, padding: 18)
        .padding(.bottom, 14)
        .shadow(color: Theme.brandDeep.opacity(0.12), radius: 10, y: 6)
    }

    @ViewBuilder private var allergyChip: some View {
        if let a = dog.allergens.first(where: { $0.severity == .hard }) {
            Chip(text: a.display, icon: "⚠", kind: .warn)
        } else {
            Chip(text: "No allergies", kind: .ok)
        }
    }
}

// MARK: - Mini ring for the dog card

struct MiniRing: View {
    @EnvironmentObject var store: AppStore
    var progress: Double

    var body: some View {
        ZStack {
            ProgressRing(progress: progress, lineWidth: 6)
            Text("\(Int((progress * 100).rounded()))%")
                .font(.milo(13, .heavy))
                .foregroundStyle(Theme.brandDeep)
        }
        .frame(width: 52, height: 52)
    }
}
