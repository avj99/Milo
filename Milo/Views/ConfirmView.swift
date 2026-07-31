import SwiftUI

/// Confirm the AI-drafted product before it saves. The owner always sees and
/// confirms what the AI read — this is the data-quality gate.
struct ConfirmView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var model: CaptureModel
    @Binding var path: [CaptureStep]
    /// Closes the whole capture flow after "Add to Fridge" (no logging).
    var onAddedToFridge: (() -> Void)? = nil

    /// Which draft is open in the editor (index into model.items).
    private struct EditTarget: Identifiable {
        let index: Int
        let product: Product
        var id: Int { index }
    }
    @State private var editing: EditTarget?

    private var product: Product { model.product ?? placeholder }

    /// Pure-rules sanity check on the drafted numbers. For a composed meal the
    /// top card is a synthesized total, so its weight-sum check is skipped —
    /// per-item checks run on the individual foods instead.
    private var plausibility: Plausibility.Result {
        Plausibility.check(product, combined: model.items.count > 1)
    }

    /// Can't continue while a food still has no calories — the owner fills it
    /// in (tap the item) rather than logging a silent zero.
    private var needsFillIn: Bool {
        (model.items.isEmpty ? [product] : model.items).contains { $0.kcalPerUnit <= 0 }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    detectingBanner
                    productCard
                    mealItemsCard
                    verifiedLine
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 150)
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
        .safeAreaInset(edge: .bottom) { cta }
        .sheet(item: $editing) { target in
            ProductEditorSheet(product: target.product) { updated in
                model.updateItem(at: target.index, with: updated)
            }
        }
    }

    /// Opens the editor for the single product, or a specific meal item.
    private func edit(_ index: Int = 0) {
        let items = model.items.isEmpty ? [product] : model.items
        guard items.indices.contains(index) else { return }
        editing = EditTarget(index: index, product: items[index])
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
            Text(model.items.count > 1
                 ? "✨ Estimated in one pass — tap any food to fix it"
                 : "✨ Check it looks right — tap the card to fix anything")
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

            field("Calories", "\(product.kcalPerUnit) kcal / \(product.portionBasis)",
                  flag: plausibility.calories)
            Divider().overlay(Theme.line)
            field("Nutrition", nutritionSummary, flag: plausibility.nutrition)
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
        .contentShape(Rectangle())
        .onTapGesture {
            // The combined meal card isn't directly editable — its items are.
            if model.items.count <= 1 { edit() }
        }
    }

    private func field(_ label: String, _ value: String, flag: String? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(alignment: .top) {
                Text(label).font(.milo(13.5, .semibold)).foregroundStyle(Theme.muted)
                Spacer()
                HStack(spacing: 7) {
                    if flag != nil {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11)).foregroundStyle(Theme.accentDeep)
                    }
                    Text(value).font(.milo(13.5, .heavy))
                        .foregroundStyle(flag == nil ? Theme.ink : Theme.accentDeep)
                        .multilineTextAlignment(.trailing)
                    Text("✎").font(.milo(12, .bold)).foregroundStyle(Theme.brand)
                }
                .frame(maxWidth: 210, alignment: .trailing)
            }
            // Orange "this looks off — double-check" note, never auto-corrected.
            if let flag {
                Text(flag)
                    .font(.milo(11.5, .bold)).foregroundStyle(Theme.accentDeep)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 230, alignment: .trailing)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.vertical, 13)
    }

    /// Guaranteed-analysis panel per portion — dashes where the label/estimate
    /// had nothing, so the owner sees exactly what's missing to fill in.
    private var nutritionSummary: String {
        func fmt(_ v: Double?, _ tag: String) -> String {
            guard let v, v > 0 else { return "– \(tag)" }
            return "\(v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v))g \(tag)"
        }
        return [fmt(product.proteinGPerUnit, "protein"),
                fmt(product.fatGPerUnit, "fat"),
                fmt(product.fiberGPerUnit, "fiber"),
                fmt(product.moistureGPerUnit, "moisture")].joined(separator: " · ")
    }

    /// For composed meals: the individual foods that will each get logged.
    @ViewBuilder private var mealItemsCard: some View {
        if model.items.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                Text("IN THIS MEAL")
                    .font(.milo(12, .heavy)).foregroundStyle(Theme.muted)
                    .padding(.leading, 4).padding(.bottom, 9)
                VStack(spacing: 0) {
                    ForEach(Array(model.items.enumerated()), id: \.offset) { index, item in
                        let itemFlag = Plausibility.check(item)
                        HStack(spacing: 11) {
                            Text(item.emoji).font(.system(size: 19))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(.milo(13.5, .heavy)).foregroundStyle(Theme.ink)
                                Text(item.portionBasis).font(.milo(11, .bold)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                            if itemFlag.isFlagged {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11)).foregroundStyle(Theme.accentDeep)
                            }
                            Text(item.kcalPerUnit == 0 ? "fill in" : "\(item.isEstimate ? "~" : "")\(item.kcalPerUnit) kcal")
                                .font(.milo(12.5, .heavy))
                                .foregroundStyle(item.kcalPerUnit == 0 ? Theme.alert
                                                 : itemFlag.isFlagged ? Theme.accentDeep : Theme.brandDeep)
                            Text("✎").font(.milo(12, .bold)).foregroundStyle(Theme.brand)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .onTapGesture { edit(index) }
                        if index < model.items.count - 1 { Divider().overlay(Theme.line) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
            }
            .padding(.top, 16)
        }
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
            PrimaryButton(title: needsFillIn ? "Fill in the calories first" : "Continue to dogs",
                          systemImage: needsFillIn ? nil : "arrow.right",
                          enabled: !needsFillIn) {
                path.append(.assign)
            }
            // Save for later without logging — it lands in My Fridge.
            Button {
                store.addToFridge(model.items.isEmpty ? [product] : model.items)
                Haptics.success()
                onAddedToFridge?()
            } label: {
                Label("Add to Fridge", systemImage: "refrigerator")
                    .font(.milo(13, .heavy))
                    .foregroundStyle(needsFillIn ? Theme.muted : Theme.brand)
                    .padding(.vertical, 8).padding(.horizontal, 16)
                    .background(Theme.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder((needsFillIn ? Theme.muted : Theme.brand).opacity(0.4), lineWidth: 1.2))
            }
            .buttonStyle(PressStyle())
            .disabled(needsFillIn)
            Text(needsFillIn ? "Tap the food marked “fill in” to add its calories"
                             : "Next: choose who this goes to")
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
