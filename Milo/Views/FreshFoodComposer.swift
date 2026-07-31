import SwiftUI

/// The Fresh tab: logging food that has no label — cooked chicken, rice,
/// fruit. Pick-first, type-second: Milo shows the foods it knows as tappable
/// chips (with live, deterministic calorie previews as you adjust portions);
/// typing is only for foods it doesn't know, which the AI estimates — still
/// in one batched pass when you continue.
struct FreshFoodComposer: View {
    /// Hands the composed meal back to the capture flow's single-pass pipeline.
    var onEstimate: ([FoodAI.MealItemInput]) -> Void

    struct FreshItem: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var emoji: String
        var portionLabel: String
        var count: Int = 1
        var isCatalog: Bool
    }

    @State private var search = ""
    @State private var meal: [FreshItem] = []
    @FocusState private var searchFocused: Bool

    private var matchingFoods: [NaturalFood] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return NaturalFoodCatalog.all }
        return NaturalFoodCatalog.all.filter {
            $0.name.contains(q) || $0.synonyms.contains(where: { $0.contains(q) })
        }
    }

    /// The typed text isn't a known food → offer it as a custom item.
    private var customCandidate: String? {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard q.count >= 3, NaturalFoodCatalog.find(q) == nil else { return nil }
        return q
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Food without a label — cooked chicken, rice, fruit. Tap what you fed; Milo already knows the numbers.")
                .font(.milo(12, .bold)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24).padding(.top, 16)

            searchField

            if !meal.isEmpty { mealCard }

            foodChips

            PrimaryButton(title: meal.isEmpty ? "Tap foods to build the meal"
                                              : "Continue · \(meal.count) \(meal.count == 1 ? "food" : "foods")",
                          systemImage: meal.isEmpty ? nil : "arrow.right",
                          enabled: !meal.isEmpty) {
                onEstimate(meal.map {
                    FoodAI.MealItemInput(name: $0.name,
                                         portion: "\($0.count) \($0.portionLabel)")
                })
            }
            .padding(.horizontal, 20).padding(.top, 18)
        }
    }

    // MARK: Search / custom entry

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
            TextField("Search foods, or type anything…", text: $search)
                .font(.milo(14.5, .heavy)).foregroundStyle(Theme.ink)
                .focused($searchFocused)
                .submitLabel(.done)
                .onSubmit { addCustomIfAny() }
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(13)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(searchFocused ? Theme.brand : Theme.line, lineWidth: 1.2))
        .padding(.horizontal, 20).padding(.top, 14)
    }

    private func addCustomIfAny() {
        guard let custom = customCandidate else { return }
        Haptics.tap()
        meal.append(FreshItem(name: custom, emoji: "🍽️",
                              portionLabel: "handful", isCatalog: false))
        search = ""
    }

    // MARK: The meal being composed

    private var mealCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THIS MEAL")
                .font(.milo(11.5, .heavy)).foregroundStyle(Theme.muted)
                .padding(.leading, 4).padding(.bottom, 8)
            VStack(spacing: 0) {
                ForEach($meal) { $item in
                    MealItemRow(item: $item) {
                        meal.removeAll { $0.id == item.id }
                    }
                    if item.id != meal.last?.id { Divider().overlay(Theme.line) }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.brand.opacity(0.35), lineWidth: 1.2))
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    // MARK: Foods Milo knows

    private var foodChips: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(search.isEmpty ? "FOODS MILO KNOWS" : "MATCHES")
                .font(.milo(11.5, .heavy)).foregroundStyle(Theme.muted)
                .padding(.leading, 24).padding(.top, 18).padding(.bottom, 9)

            ChipFlow(spacing: 8) {
                if let custom = customCandidate {
                    Button(action: addCustomIfAny) {
                        chipLabel(emoji: "✨", text: "Add “\(custom)”", highlighted: true)
                    }
                    .buttonStyle(PressStyle())
                }
                ForEach(matchingFoods, id: \.name) { food in
                    Button {
                        Haptics.tap()
                        meal.append(FreshItem(
                            name: food.name,
                            emoji: food.emoji,
                            portionLabel: food.portions.first?.label
                                ?? NaturalFoodCatalog.genericPortions[0].label,
                            isCatalog: true))
                        search = ""
                    } label: {
                        chipLabel(emoji: food.emoji, text: food.name.capitalized,
                                  highlighted: false)
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(.horizontal, 20)

            if matchingFoods.isEmpty && customCandidate == nil {
                Text("Keep typing — you can add any food and Milo's AI will estimate it.")
                    .font(.milo(12, .bold)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8).padding(.horizontal, 24)
            }
        }
    }

    private func chipLabel(emoji: String, text: String, highlighted: Bool) -> some View {
        HStack(spacing: 6) {
            Text(emoji).font(.system(size: 15))
            Text(text).font(.milo(12.5, .heavy))
                .foregroundStyle(highlighted ? .white : Theme.ink)
        }
        .padding(.vertical, 9).padding(.horizontal, 12)
        .background(highlighted ? Theme.brand : Theme.card)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(highlighted ? .clear : Theme.line, lineWidth: 1))
    }
}

/// Left-aligned wrapping layout — chips hug their text and flow onto the
/// next line, so food names never truncate.
struct ChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - One food in the meal: count stepper + portion picker + live kcal

private struct MealItemRow: View {
    @Binding var item: FreshFoodComposer.FreshItem
    var onRemove: () -> Void

    /// Instant, deterministic preview for catalog foods; unknown foods say AI.
    private var kcalPreview: String {
        guard item.isCatalog,
              let estimate = NaturalFoodCatalog.estimate(
                name: item.name, portion: "\(item.count) \(item.portionLabel)")
        else { return "AI will estimate" }
        return "~\(estimate.kcalPerUnit) kcal"
    }

    private var portionOptions: [String] {
        var options = NaturalFoodCatalog.find(item.name)?.portions.map(\.label) ?? []
        for generic in NaturalFoodCatalog.genericPortions.map(\.label)
        where !options.contains(generic) {
            options.append(generic)
        }
        return options
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(item.emoji).font(.system(size: 19))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.capitalized)
                    .font(.milo(13.5, .heavy)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(kcalPreview)
                    .font(.milo(11, .bold))
                    .foregroundStyle(item.isCatalog ? Theme.brandDeep : Theme.muted)
            }
            Spacer(minLength: 6)

            // How many…
            HStack(spacing: 0) {
                Button { Haptics.tap(); item.count = max(1, item.count - 1) } label: {
                    Text("−").font(.milo(15, .heavy)).frame(width: 26, height: 28)
                }
                Text("\(item.count)")
                    .font(.milo(12.5, .heavy)).foregroundStyle(Theme.ink)
                    .frame(minWidth: 18)
                Button { Haptics.tap(); item.count = min(20, item.count + 1) } label: {
                    Text("＋").font(.milo(14, .heavy)).frame(width: 26, height: 28)
                }
            }
            .foregroundStyle(Theme.brandDeep)
            .background(Theme.track)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            // …of what
            Menu {
                ForEach(portionOptions, id: \.self) { option in
                    Button {
                        item.portionLabel = option
                    } label: {
                        if option == item.portionLabel {
                            Label(option, systemImage: "checkmark")
                        } else {
                            Text(option)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(item.portionLabel).font(.milo(12, .heavy)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Theme.brandDeep)
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(Theme.track)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17)).foregroundStyle(Theme.muted.opacity(0.7))
            }
        }
        .padding(.vertical, 10)
    }
}
