import SwiftUI

struct HouseholdView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    inviteCard
                    SectionHeader("People").padding(.vertical, 12)
                    ForEach(store.members) { member in
                        MemberRow(member: member, subtitle: subtitle(for: member))
                    }
                    walkerRow

                    SectionHeader("How Milo avoids double-feeding")
                        .padding(.top, 18).padding(.bottom, 10)
                    doubleFeederNudge

                    Text("Everyone in a household is equal. Leaving keeps the dogs and their history with the household.")
                        .font(.milo(11.5, .bold))
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16).padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            BackButton { dismiss() }
            VStack(alignment: .leading, spacing: 1) {
                Text(store.household?.name ?? "Your household")
                    .font(.milo(19, .heavy)).foregroundStyle(Theme.ink)
                Text("\(store.dogs.count) dogs · \(store.members.count) people · everyone sees the same day")
                    .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var inviteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Invite the household").font(.milo(15, .heavy)).foregroundStyle(.white)
            Text("Anyone with the code joins the shared dashboard. They can log meals and treats, and everyone sees who fed the dogs — live.")
                .font(.milo(12, .semibold)).foregroundStyle(.white.opacity(0.85))
                .padding(.top, 4)

            HStack {
                Text(store.household?.inviteCode ?? "—")
                    .font(.milo(22, .heavy)).foregroundStyle(.white)
                    .kerning(4)
                Spacer()
                Button {
                    copied = true
                    UIPasteboard.general.string = store.household?.inviteCode ?? ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                } label: {
                    Text(copied ? "Copied ✓" : "Copy link")
                        .font(.milo(12, .heavy)).foregroundStyle(Theme.brandDeep)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
            .padding(14)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 14)
        }
        .padding(20)
        .background(Theme.brandGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 4)
    }

    private var walkerRow: some View {
        HStack(spacing: 13) {
            Text("＋")
                .font(.milo(15, .heavy)).foregroundStyle(Theme.brand)
                .frame(width: 44, height: 44)
                .background(Theme.card)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.brand, style: StrokeStyle(lineWidth: 2, dash: [4])))
            VStack(alignment: .leading, spacing: 1) {
                Text("Add the dog-walker or sitter").font(.milo(15, .heavy)).foregroundStyle(Theme.ink)
                Text("Send a view-only link — they see the plan, don't need an account")
                    .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
        .padding(.top, 2)
    }

    private var doubleFeederNudge: some View {
        HStack(alignment: .top, spacing: 11) {
            Text("🥣").font(.system(size: 19))
            VStack(alignment: .leading, spacing: 3) {
                Text("Bella was already fed breakfast")
                    .font(.milo(13.5, .heavy)).foregroundStyle(Theme.accentDeep)
                Text("Mom logged ¾ cup 8 minutes ago. When someone starts a second breakfast-sized meal, Milo asks first — \u{201C}Log anyway?\u{201D} — so nobody accidentally feeds her twice.")
                    .font(.milo(12, .semibold)).foregroundStyle(Color(hex: 0x9A7B32))
            }
        }
        .padding(14)
        .background(Theme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color(hex: 0xEBCD93), lineWidth: 1))
    }

    private func subtitle(for m: Member) -> String {
        if m.isYou { return "Owner" }
        switch m.name {
        case "Mom":  return "Created the household · fed Bella 4 min ago"
        case "Dad":  return "Logged breakfast · 7:20 AM"
        case "Emma": return "Logged a dental chew · 1:05 PM"
        default:     return "Member"
        }
    }
}

struct MemberRow: View {
    var member: Member
    var subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            Text(member.initials)
                .font(.milo(16, .heavy)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(member.palette.gradient)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(member.name).font(.milo(15, .heavy)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Text(member.isYou ? "You" : "Member")
                .font(.milo(10.5, .heavy))
                .foregroundStyle(member.isYou ? Theme.accentDeep : Theme.muted)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(member.isYou ? Theme.accentSoft : Theme.track)
                .clipShape(Capsule())
        }
        .padding(14)
        .miloCard(radius: 18, padding: 0)
        .padding(.bottom, 10)
    }
}
