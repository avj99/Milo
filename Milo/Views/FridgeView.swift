import SwiftUI

/// "My Fridge" — the household's shared food database. Everything anyone has
/// ever captured or logged lives here (synced via the products table), grouped
/// by category. From here you can log a food again in two taps, stock the
/// fridge with new foods, or throw things out.
struct FridgeView: View {
    @EnvironmentObject var store: AppStore
    /// Opens the capture flow (Package / Natural / Manual) to stock the fridge.
    var onAddFood: () -> Void

    @State private var logProduct: Product?

    private var grouped: [(category: FoodCategory, items: [Product])] {
        FoodCategory.allCases.compactMap { category in
            let items = store.favorites.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if store.favorites.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped, id: \.category) { group in
                            sectionHeader(group.category, count: group.items.count)
                            ForEach(group.items) { item in
                                FridgeRow(product: item,
                                          onLog: { logProduct = item },
                                          onDelete: { store.removeFromFridge(item) })
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 130)
                }
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .sheet(item: $logProduct) { product in
            FridgeLogSheet(product: product)
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("My Fridge").font(.milo(22, .heavy)).foregroundStyle(Theme.ink)
                Text(store.favorites.isEmpty
                     ? "The household's foods live here"
                     : "\(store.favorites.count) foods · whole household")
                    .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button(action: onAddFood) {
                Label("Add food", systemImage: "plus")
                    .font(.milo(13, .heavy))
                    .foregroundStyle(.white)
                    .padding(.vertical, 9).padding(.horizontal, 14)
                    .background(Theme.brand)
                    .clipShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(Theme.bg)
    }

    private func sectionHeader(_ category: FoodCategory, count: Int) -> some View {
        HStack(spacing: 7) {
            Text(category.emoji).font(.system(size: 14))
            Text(category.label.uppercased()).font(.milo(12, .heavy)).foregroundStyle(Theme.muted)
            Text("\(count)").font(.milo(11, .heavy)).foregroundStyle(Theme.muted.opacity(0.7))
            Spacer()
        }
        .padding(.top, 20).padding(.bottom, 9).padding(.leading, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🧊").font(.system(size: 52))
            Text("The fridge is empty").font(.milo(17, .heavy)).foregroundStyle(Theme.ink)
            Text("Foods you capture or log are kept here for the whole household — one tap to feed again.")
                .font(.milo(13, .semibold)).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Button(action: onAddFood) {
                Text("Add the first food")
                    .font(.milo(14, .heavy)).foregroundStyle(.white)
                    .padding(.vertical, 12).padding(.horizontal, 22)
                    .background(Theme.brand)
                    .clipShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .padding(.top, 6)
        }
        .padding(.bottom, 60)
    }
}

// MARK: - Row

private struct FridgeRow: View {
    var product: Product
    var onLog: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Text(product.emoji).font(.system(size: 21))
                .frame(width: 42, height: 42)
                .background(Theme.track)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(product.name).font(.milo(14.5, .heavy)).foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle).font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onLog) {
                Text("＋").font(.milo(20, .heavy)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressStyle())
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .miloCard(radius: 18, padding: 0)
        .padding(.bottom, 10)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Remove from Fridge", systemImage: "trash")
            }
        }
    }

    private var subtitle: String {
        let kcal = product.isEstimate ? "~\(product.kcalPerUnit)" : "\(product.kcalPerUnit)"
        let brand = product.brand.isEmpty ? "" : " · \(product.brand)"
        return "\(kcal) kcal / \(product.portionBasis)\(brand)"
    }
}

// MARK: - Log-again sheet (straight to Assign)

private struct FridgeLogSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var product: Product
    @StateObject private var model = CaptureModel()

    var body: some View {
        NavigationStack {
            AssignView(model: model, onDone: { dismiss() })
        }
        .onAppear {
            model.prepare(product: product, dogs: store.dogs, fromAIDraft: false)
        }
    }
}
