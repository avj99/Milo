import SwiftUI

/// Confirm the AI-drafted product before it saves. The owner always sees and
/// confirms what the AI read — this is the data-quality gate.
struct ConfirmView: View {
    @ObservedObject var model: CaptureModel
    @Binding var path: [CaptureStep]

    private var product: Product { model.product ?? placeholder }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detectingBanner
                    productCard
                    verifiedLine
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 150)
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { cta }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            BackButton { path.removeLast() }
            Text("Confirm the food").font(.milo(19, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var detectingBanner: some View {
        HStack(spacing: 8) {
            Text("✨ AI read the label — check it looks right")
        }
        .font(.milo(12.5, .heavy))
        .foregroundStyle(Theme.accentDeep)
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Theme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 16)
    }

    private var productCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(product.emoji).font(.system(size: 34))
                    .frame(width: 66, height: 66)
                    .background(LinearGradient(colors: [Color(hex: 0xF6D9A0), Color(hex: 0xE7A94E)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.milo(17, .heavy)).foregroundStyle(Theme.ink)
                    Text("\(product.brand) · \(product.category.label.lowercased())")
                        .font(.milo(12.5, .bold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)

            field("Calories", "\(product.kcalPerUnit) kcal / \(product.portionBasis)")
            Divider().overlay(Theme.line)
            field("Main ingredients", product.ingredients.map { $0.capitalized }.joined(separator: ", "))
            Divider().overlay(Theme.line)
            field("Category", product.category.label)
        }
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Theme.line, lineWidth: 1))
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.milo(13.5, .semibold)).foregroundStyle(Theme.muted)
            Spacer()
            HStack(spacing: 7) {
                Text(value).font(.milo(13.5, .heavy)).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.trailing)
                Text("✎").font(.milo(12, .bold)).foregroundStyle(Theme.brand)
            }
            .frame(maxWidth: 210, alignment: .trailing)
        }
        .padding(.vertical, 13)
    }

    @ViewBuilder private var verifiedLine: some View {
        if !product.verified {
            (Text("🔎 New to the database — saved as ")
                .foregroundStyle(Theme.muted)
             + Text("unverified").foregroundStyle(Theme.ink).bold()
             + Text(" until a few owners confirm it. Photo kept on file.")
                .foregroundStyle(Theme.muted))
            .font(.milo(11.5, .semibold))
            .padding(.horizontal, 4).padding(.top, 14)
        }
    }

    private var cta: some View {
        VStack(spacing: 9) {
            PrimaryButton(title: "Continue to dogs", systemImage: "arrow.right") {
                path.append(.assign)
            }
            Text("Next: choose who this goes to")
                .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
    }

    private var placeholder: Product {
        Product(name: "—", brand: "", emoji: "🍗", category: .treat,
                kcalPerUnit: 0, portionBasis: "piece", ingredients: [])
    }
}
