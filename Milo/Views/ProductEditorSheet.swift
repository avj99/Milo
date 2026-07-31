import SwiftUI

/// The manual-verification editor behind Confirm's ✎ affordances. Everything
/// the OCR/AI drafted can be corrected here; anything it missed can be filled
/// in. Saves back a complete Product (same id — never a duplicate).
struct ProductEditorSheet: View {
    var product: Product
    var onSave: (Product) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var brand = ""
    @State private var emoji = "🥣"
    @State private var category: FoodCategory = .kibble
    @State private var kcalText = ""
    @State private var portion = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var fiberText = ""
    @State private var moistureText = ""
    @State private var ingredientsText = ""
    @FocusState private var focused: Bool

    private var kcal: Int { Int(kcalText.trimmingCharacters(in: .whitespaces)) ?? 0 }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && kcal > 0
            && !portion.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        row("Name") { field("Food name", $name) }
                        row("Brand") { field("Optional", $brand) }
                        row("Category") { categoryChips }
                        HStack(alignment: .top, spacing: 12) {
                            row("Calories") { field("kcal", $kcalText, keyboard: .numberPad) }
                            row("Per portion") { field("e.g. ¾ cup", $portion) }
                        }
                        HStack(alignment: .top, spacing: 12) {
                            row("Protein (g)") { field("optional", $proteinText, keyboard: .decimalPad) }
                            row("Fat (g)") { field("optional", $fatText, keyboard: .decimalPad) }
                        }
                        HStack(alignment: .top, spacing: 12) {
                            row("Fiber (g)") { field("optional", $fiberText, keyboard: .decimalPad) }
                            row("Moisture (g)") { field("optional", $moistureText, keyboard: .decimalPad) }
                        }
                        row("Ingredients (comma-separated)") { field("e.g. salmon, rice, peas", $ingredientsText) }
                        allergenPreview
                    }
                    .padding(.horizontal, 20).padding(.bottom, 30)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Check & fill in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        name = product.name == "Scanned food" ? "" : product.name
        brand = product.brand
        emoji = product.emoji
        category = product.category
        kcalText = product.kcalPerUnit > 0 ? "\(product.kcalPerUnit)" : ""
        portion = product.portionBasis
        proteinText = gramsText(product.proteinGPerUnit)
        fatText = gramsText(product.fatGPerUnit)
        fiberText = gramsText(product.fiberGPerUnit)
        moistureText = gramsText(product.moistureGPerUnit)
        ingredientsText = product.ingredients.joined(separator: ", ")
    }

    private func save() {
        func grams(_ text: String) -> Double? {
            let v = Double(text.trimmingCharacters(in: .whitespaces)) ?? 0
            return v > 0 ? v : nil
        }
        let ingredients = ingredientsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        onSave(Product(
            id: product.id,                      // same id — edits never duplicate
            name: name.trimmingCharacters(in: .whitespaces),
            brand: brand.trimmingCharacters(in: .whitespaces),
            emoji: category == product.category ? emoji : category.emoji,
            category: category,
            kcalPerUnit: kcal,
            portionBasis: portion.trimmingCharacters(in: .whitespaces),
            ingredients: ingredients,
            verified: true,                      // a human checked it
            isEstimate: product.isEstimate,
            proteinGPerUnit: grams(proteinText),
            fatGPerUnit: grams(fatText),
            fiberGPerUnit: grams(fiberText),
            moistureGPerUnit: grams(moistureText)))
        Haptics.tap()
        dismiss()
    }

    private func gramsText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "" }
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: pieces

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.milo(11.5, .heavy)).foregroundStyle(Theme.muted)
                .padding(.leading, 4).padding(.top, 16).padding(.bottom, 8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ placeholder: String, _ text: Binding<String>,
                       keyboard: UIKeyboardType = .default) -> some View {
        TextField(placeholder, text: text)
            .font(.milo(15, .heavy)).foregroundStyle(Theme.ink)
            .keyboardType(keyboard)
            .padding(13)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1))
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(FoodCategory.allCases) { c in
                    HStack(spacing: 5) {
                        Text(c.emoji).font(.system(size: 13))
                        Text(c.label).font(.milo(12.5, .heavy))
                    }
                    .foregroundStyle(category == c ? Theme.brandDeep : Theme.muted)
                    .padding(.vertical, 9).padding(.horizontal, 13)
                    .background(category == c ? Theme.card : .clear)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(category == c ? Theme.brand : .clear, lineWidth: 1.2))
                    .onTapGesture {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.15)) { category = c }
                    }
                }
            }
            .padding(5)
        }
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var allergenPreview: some View {
        let detected = AllergenEngine.normalize(
            ingredientsText.split(separator: ",").map { String($0) }).sorted()
        if !detected.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text("Milo will check these against each dog")
                    .font(.milo(11, .bold)).foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    ForEach(detected, id: \.self) { a in
                        Chip(text: a.capitalized, icon: "⚠", kind: .warn)
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}
