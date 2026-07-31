import SwiftUI

/// "One dog or the whole pack — each gets their own portion and their own check."
/// Assigning to many spawns one log entry per selected dog. Each dog is checked
/// against the product's ingredients individually, so a chicken treat assigned to
/// three dogs flags only the dog who reacts to chicken.
struct AssignView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var model: CaptureModel
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmAllergyOverride = false

    private var product: Product { model.product ?? placeholder }

    private var selectedDogs: [Dog] {
        store.dogs.filter { model.selection[$0.id] == true }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("One dog or the whole pack — each gets their own portion and their own check.")
                        .font(.milo(13.5, .semibold)).foregroundStyle(Theme.muted)
                        .padding(.vertical, 4)

                    allButton.padding(.vertical, 12)

                    ForEach(store.dogs) { dog in
                        AssignRow(dog: dog, product: product, model: model)
                            .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 170)
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { cta }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            BackButton { dismiss() }
            Text("Add to which dogs?").font(.milo(19, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var allSelected: Bool {
        !store.dogs.isEmpty && store.dogs.allSatisfy { model.selection[$0.id] == true }
    }

    private var allButton: some View {
        Button {
            let turnOn = !allSelected
            for d in store.dogs { model.selection[d.id] = turnOn }
        } label: {
            HStack(spacing: 8) {
                Text(allSelected ? "✓ All dogs selected" : "🐾 Add to all dogs")
            }
            .font(.milo(14, .heavy))
            .foregroundStyle(allSelected ? Theme.brand : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(allSelected ? Theme.card : Theme.brand)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rPill, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.rPill, style: .continuous)
                .strokeBorder(Theme.brand, lineWidth: allSelected ? 1.5 : 0))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: CTA reflects who is selected + the allergy caveat.

    private var cta: some View {
        VStack(spacing: 9) {
            PrimaryButton(title: ctaTitle, systemImage: selectedDogs.isEmpty ? nil : "arrow.right",
                          enabled: !selectedDogs.isEmpty) {
                // Overriding a hard allergy must be a deliberate, second tap.
                if allergicSelected.isEmpty {
                    logNow()
                } else {
                    Haptics.warning()
                    confirmAllergyOverride = true
                }
            }
            Text(subText)
                .font(.milo(11.5, .bold))
                .foregroundStyle(subColor)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 20)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.35)))
        .confirmationDialog(allergyDialogTitle,
                            isPresented: $confirmAllergyOverride,
                            titleVisibility: .visible) {
            Button("Log anyway", role: .destructive) { logNow() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This food lists an ingredient they react to. Milo will keep the entry flagged.")
        }
    }

    private var allergyDialogTitle: String {
        let names = allergicSelected.map(\.name)
        let who = names.count == 1 ? names[0] : names.joined(separator: " & ")
        let what = allergicSelected.first
            .flatMap { dog in AllergenEngine.flags(for: dog, product: product).first?.canonical }
            ?? "an allergen"
        return "\(who) is allergic to \(what)"
    }

    /// One entry per food per dog — captured together, calculated together,
    /// logged together.
    private func logNow() {
        let assignments = selectedDogs.map {
            (dog: $0, portionCount: model.portions[$0.id] ?? 1)
        }
        let foods = model.items.isEmpty ? [product] : model.items
        for food in foods {
            store.logProduct(food, to: assignments, by: store.currentMember)
        }
        Haptics.success()
        onDone()
    }

    private var ctaTitle: String {
        let names = selectedDogs.map(\.name)
        if names.isEmpty { return "Pick a dog" }
        return "Log to " + names.joined(separator: " & ")
    }

    private var allergicSelected: [Dog] {
        selectedDogs.filter { AllergenEngine.hasHardFlag(for: $0, product: product) }
    }

    private var subText: String {
        if selectedDogs.isEmpty { return "Select at least one dog to log this" }
        if let dog = allergicSelected.first {
            return "⚠️ \(dog.name) is allergic — logging anyway"
        }
        // Someone with an allergy exists but is not selected → reassure.
        if let skipped = store.dogs.first(where: {
            model.selection[$0.id] != true && AllergenEngine.hasHardFlag(for: $0, product: product)
        }) {
            return "\(skipped.name) skipped — allergic to an ingredient here"
        }
        return "Each dog gets its own entry and calorie check"
    }

    private var subColor: Color {
        allergicSelected.isEmpty ? Theme.muted : Theme.alert
    }

    private var placeholder: Product {
        Product(name: "—", brand: "", emoji: "🍗", category: .treat,
                kcalPerUnit: 0, portionBasis: "piece", ingredients: [])
    }
}

// MARK: - Assign row

struct AssignRow: View {
    @EnvironmentObject var store: AppStore
    var dog: Dog
    var product: Product
    @ObservedObject var model: CaptureModel

    private var selected: Bool { model.selection[dog.id] == true }
    private var count: Int { model.portions[dog.id] ?? 1 }
    private var flags: [Allergen] { AllergenEngine.flags(for: dog, product: product) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                checkCircle
                VStack(alignment: .leading, spacing: 1) {
                    Text(dog.name).font(.milo(15.5, .heavy)).foregroundStyle(Theme.ink)
                    Text("\(dog.breed) · \(store.remaining(for: dog)) kcal left today")
                        .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                stepper
            }
            .contentShape(Rectangle())
            .onTapGesture { model.selection[dog.id] = !selected }

            if let flag = flags.first(where: { $0.severity == .hard }) {
                allergyFlag(flag)
            }

            HStack {
                Text(selected ? "Adds to their day" : "Not selected")
                Spacer()
                Text("+\(product.kcalPerUnit * count) kcal")
                    .foregroundStyle(Theme.brandDeep)
            }
            .font(.milo(11.5, .heavy))
            .foregroundStyle(Theme.muted)
            .padding(.top, 11)
        }
        .padding(15)
        .background(selected ? Color(hex: 0xF6FAF7) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(selected ? Theme.brand : Theme.line, lineWidth: 1.5))
    }

    private var checkCircle: some View {
        ZStack {
            Circle()
                .fill(selected ? Theme.brand : .clear)
                .overlay(Circle().strokeBorder(selected ? Theme.brand : Theme.line, lineWidth: 2))
            if selected {
                Image(systemName: "checkmark").font(.milo(13, .heavy)).foregroundStyle(.white)
            }
        }
        .frame(width: 26, height: 26)
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.tap()
                model.portions[dog.id] = max(1, count - 1)
                model.selection[dog.id] = true
            } label: { stepGlyph("−") }
            Text(portionLabel)
                .font(.milo(12.5, .heavy)).foregroundStyle(Theme.ink)
                .frame(minWidth: 58)
            Button {
                Haptics.tap()
                model.portions[dog.id] = min(12, count + 1)
                model.selection[dog.id] = true
            } label: { stepGlyph("＋") }
        }
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func stepGlyph(_ s: String) -> some View {
        Text(s).font(.milo(17, .heavy)).foregroundStyle(Theme.brandDeep)
            .frame(width: 30, height: 32)
    }

    private var portionLabel: String {
        let unit = product.portionBasis
        if unit == "piece" { return "\(count) " + (count == 1 ? "piece" : "pieces") }
        return count == 1 ? unit : "\(count)× \(unit)"
    }

    private func allergyFlag(_ flag: Allergen) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("⚠️").font(.system(size: 15))
            (Text("\(dog.name) is allergic to \(flag.canonical). ").bold()
             + Text("This lists \(flag.canonical) — we'd skip it. Tap to add anyway."))
                .font(.milo(12, .semibold))
                .foregroundStyle(Theme.alert)
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.alertSoft)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 12)
    }
}
