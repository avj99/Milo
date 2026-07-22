import SwiftUI

/// Type in a food's nutrition details by hand. Per the build guide, the manual
/// path is never removed — it's the fast, honest way to capture the things an
/// owner feeds every day, and it feeds the same product/allergy pipeline as the
/// AI capture flow. Ingredients typed here run through the allergen engine live,
/// so the owner can see who Milo would flag before logging.
struct ManualEntryView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var model: CaptureModel
    @Binding var path: [CaptureStep]

    @State private var emoji = "🥣"
    @State private var name = ""
    @State private var brand = ""
    @State private var category: FoodCategory = .meal
    @State private var kcalText = ""
    @State private var portion = ""
    @State private var ingredientsText = ""
    @State private var isEstimate = false
    @FocusState private var focus: Field?

    private enum Field { case name, brand, kcal, portion, ingredients }

    private let emojiOptions = ["🥣", "🍗", "🦴", "🍖", "🐟", "🥩", "🍚", "🥕", "🧀", "🥚"]

    // MARK: Derived

    private var kcal: Int? {
        let v = Int(kcalText.trimmingCharacters(in: .whitespaces))
        return (v ?? 0) > 0 ? v : nil
    }

    private var ingredients: [String] {
        ingredientsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var detectedAllergens: [String] {
        AllergenEngine.normalize(ingredients).sorted()
    }

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && kcal != nil
            && !portion.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    emojiSection
                    labeled("Name") {
                        textField("e.g. Grain-free salmon kibble", text: $name, field: .name)
                    }
                    labeled("Brand (optional)") {
                        textField("e.g. Happy Tails", text: $brand, field: .brand)
                    }
                    labeled("Category") { categorySegmented }
                    HStack(alignment: .top, spacing: 12) {
                        labeled("Calories") {
                            textField("kcal", text: $kcalText, field: .kcal, keyboard: .numberPad)
                        }
                        labeled("Per portion") {
                            textField("e.g. ¾ cup", text: $portion, field: .portion)
                        }
                    }
                    labeled("Ingredients") {
                        VStack(alignment: .leading, spacing: 0) {
                            textField("Comma-separated, e.g. salmon, rice, peas",
                                      text: $ingredientsText, field: .ingredients)
                            allergenPreview
                        }
                    }
                    estimateToggle
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { cta }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack(spacing: 12) {
            BackButton { path.removeLast() }
            Text("Add a food").font(.milo(19, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var emojiSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            formLabel("Icon")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    ForEach(emojiOptions, id: \.self) { e in
                        Text(e).font(.system(size: 26))
                            .frame(width: 50, height: 50)
                            .background(emoji == e ? Color(hex: 0xF6FAF7) : Theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(emoji == e ? Theme.brand : Theme.line,
                                              lineWidth: emoji == e ? 1.5 : 1))
                            .scaleEffect(emoji == e ? 1.05 : 1)
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.15)) { emoji = e }
                            }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var categorySegmented: some View {
        HStack(spacing: 7) {
            ForEach(FoodCategory.allCases) { c in
                Text(c.label)
                    .font(.milo(12.5, .heavy))
                    .foregroundStyle(category == c ? Theme.brandDeep : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(category == c ? Theme.card : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: category == c ? Theme.brandDeep.opacity(0.15) : .clear, radius: 5, y: 3)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { category = c } }
            }
        }
        .padding(5)
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var allergenPreview: some View {
        if !detectedAllergens.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Milo will check these against each dog")
                    .font(.milo(11, .bold)).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    ForEach(detectedAllergens, id: \.self) { a in
                        Chip(text: a.capitalized, icon: "⚠", kind: .warn)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private var estimateToggle: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Portion is an estimate").font(.milo(14, .heavy)).foregroundStyle(Theme.ink)
                Text("For scooped or hand-fed add-ins — logs the calories as a range")
                    .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $isEstimate).labelsHidden().tint(Theme.brand)
        }
        .padding(14)
        .miloCard(radius: 18, padding: 0)
        .padding(.top, 18)
    }

    private var cta: some View {
        VStack(spacing: 9) {
            PrimaryButton(title: "Continue to dogs", systemImage: canContinue ? "arrow.right" : nil,
                          enabled: canContinue) {
                let product = Product(
                    name: name.trimmingCharacters(in: .whitespaces),
                    brand: brand.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Manual entry" : brand.trimmingCharacters(in: .whitespaces),
                    emoji: emoji, category: category,
                    kcalPerUnit: kcal ?? 0,
                    portionBasis: portion.trimmingCharacters(in: .whitespaces),
                    ingredients: ingredients,
                    verified: true, isEstimate: isEstimate)
                model.prepare(product: product, dogs: store.dogs, fromAIDraft: false)
                path.append(.assign)
            }
            Text(canContinue ? "Next: choose who this goes to" : "Add a name, calories and portion to continue")
                .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
    }

    // MARK: Building blocks

    private func labeled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            formLabel(label)
            content()
        }
    }

    private func formLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.milo(12, .heavy)).foregroundStyle(Theme.muted)
            .padding(.leading, 4).padding(.top, 18).padding(.bottom, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func textField(_ placeholder: String, text: Binding<String>,
                           field: Field, keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(.milo(15, .heavy)).foregroundStyle(Theme.ink)
            .keyboardType(keyboard)
            .focused($focus, equals: field)
            .padding(14)
            .background(focus == field ? Theme.card : Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focus == field ? Theme.brand : Theme.line, lineWidth: 1.5))
    }
}
