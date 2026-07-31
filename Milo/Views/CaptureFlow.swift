import SwiftUI

// The "capture once → assign to many" pipeline, presented as a modal flow:
//   Capture (Package / Natural / Manual) → Confirm the draft → Assign to dogs.
// Package = two guided photos (front + nutrition label) → OCR → on-device AI.
// Natural = type the whole meal, then ONE batch estimate (catalog + AI) —
// never a model call per item. Manual quick-log skips Confirm.

enum CaptureStep: Hashable, Identifiable {
    case scan       // capture root
    case confirm
    case manualForm
    case assign
    var id: Self { self }
}

@MainActor
final class CaptureModel: ObservableObject {
    @Published var product: Product?
    @Published var fromAIDraft = false

    /// The individual foods being logged. One entry for a single product;
    /// several for a composed natural meal (each becomes its own LogEntry).
    @Published var items: [Product] = []

    /// Per-dog selection + portion, keyed by dog id.
    @Published var selection: [UUID: Bool] = [:]
    @Published var portions: [UUID: Int] = [:]

    func prepare(product: Product, dogs: [Dog], fromAIDraft: Bool) {
        self.product = product
        self.items = [product]
        self.fromAIDraft = fromAIDraft
        for d in dogs {
            selection[d.id] = true
            portions[d.id] = 1
        }
    }

    /// A composed meal: keeps every item for logging, and synthesizes a
    /// combined product so Confirm/Assign can show totals and run the
    /// per-dog allergy check across ALL ingredients at once.
    func prepareMeal(_ products: [Product], dogs: [Dog]) {
        guard !products.isEmpty else { return }
        if products.count == 1 {
            prepare(product: products[0], dogs: dogs, fromAIDraft: true)
            return
        }
        product = Self.combined(from: products)
        items = products
        fromAIDraft = true
        for d in dogs {
            selection[d.id] = true
            portions[d.id] = 1
        }
    }

    /// Writes an edited draft back — single edits replace the product; meal
    /// item edits recompute the combined totals.
    func updateItem(at index: Int, with edited: Product) {
        guard items.indices.contains(index) else {
            product = edited
            items = [edited]
            return
        }
        items[index] = edited
        product = items.count == 1 ? edited : Self.combined(from: items)
    }

    static func combined(from products: [Product]) -> Product {
        func total(_ keyPath: KeyPath<Product, Double?>) -> Double? {
            let values = products.compactMap { $0[keyPath: keyPath] }
            return values.isEmpty ? nil : values.reduce(0, +)
        }
        return Product(
            name: "Meal · \(products.count) foods",
            brand: "",
            emoji: "🍽️",
            category: .other,
            kcalPerUnit: products.reduce(0) { $0 + $1.kcalPerUnit },
            portionBasis: "meal",
            ingredients: Array(Set(products.flatMap(\.ingredients))),
            verified: false,
            isEstimate: products.contains(where: \.isEstimate),
            proteinGPerUnit: total(\.proteinGPerUnit),
            fatGPerUnit: total(\.fatGPerUnit),
            fiberGPerUnit: total(\.fiberGPerUnit),
            moistureGPerUnit: total(\.moistureGPerUnit))
    }
}

struct CaptureFlow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CaptureModel()
    @State private var path: [CaptureStep] = []

    /// Optional deep-link entry point (used for verification screenshots).
    var initialStep: CaptureStep? = nil

    /// Sample draft for the DEBUG deep-link (screenshot verification only).
    static let aiDraft = Product(
        name: "Chicken Jerky Bites", brand: "Happy Tails", emoji: "🍗",
        category: .treat, kcalPerUnit: 32, portionBasis: "piece",
        ingredients: ["chicken breast", "glycerin", "salt"], verified: false)

    #if DEBUG
    /// An intentionally implausible draft (as if OCR misread the guaranteed
    /// analysis) — used to verify the Confirm plausibility guardrails render.
    /// Reached via MILO_CONFIRM_SAMPLE=implausible.
    static let implausibleDraft = Product(
        name: "Salmon Dry Recipe", brand: "Northwood", emoji: "🥣",
        category: .kibble, kcalPerUnit: 1500, portionBasis: "cup",
        ingredients: ["salmon", "brown rice", "peas"], verified: false,
        isEstimate: true, proteinGPerUnit: 300, fatGPerUnit: 120,
        fiberGPerUnit: 8, moistureGPerUnit: 12)
    #endif

    var body: some View {
        NavigationStack(path: $path) {
            CaptureView(model: model, path: $path, onClose: { dismiss() })
                .navigationDestination(for: CaptureStep.self) { step in
                    switch step {
                    case .confirm:    ConfirmView(model: model, path: $path,
                                                  onAddedToFridge: { dismiss() })
                    case .manualForm: ManualEntryView(model: model, path: $path)
                    case .assign:     AssignView(model: model, onDone: { dismiss() })
                    case .scan:       EmptyView()
                    }
                }
        }
        .environmentObject(model)
        .onAppear {
            if let step = initialStep, step != .scan {
                var draft = Self.aiDraft
                #if DEBUG
                if ProcessInfo.processInfo.environment["MILO_CONFIRM_SAMPLE"] == "implausible" {
                    draft = Self.implausibleDraft
                }
                #endif
                model.prepare(product: draft, dogs: store.dogs, fromAIDraft: true)
                path = [step]
            }
        }
    }
}

// MARK: - Capture

struct CaptureView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var model: CaptureModel
    @Binding var path: [CaptureStep]
    var onClose: () -> Void

    enum Mode: String, CaseIterable { case package = "Package", natural = "Fresh", manual = "Manual" }
    @State private var mode: Mode = .package

    // Package: the guided two-shot
    private enum Shot { case front, back }
    @State private var frontImage: UIImage?
    @State private var backImage: UIImage?
    @State private var pendingShot: Shot?

    // Shared pipeline state
    @State private var busy = false
    @State private var busyLabel = ""
    @State private var notice: String?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    segmented
                    switch mode {
                    case .package: packagePanel
                    case .natural: naturalPanel
                    case .manual:  manualPanel
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            if busy {
                Color.black.opacity(0.25).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(busyLabel).font(.milo(14, .bold)).foregroundStyle(.white)
                }
                .padding(24)
                .background(Color(hex: 0x1B2B25, alpha: 0.9))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
        .onAppear {
            #if DEBUG
            // Screenshot deep-link: MILO_CAPTURE_MODE=fresh|manual
            switch ProcessInfo.processInfo.environment["MILO_CAPTURE_MODE"] {
            case "fresh":  mode = .natural
            case "manual": mode = .manual
            default: break
            }
            #endif
        }
        .sheet(isPresented: Binding(get: { pendingShot != nil },
                                    set: { if !$0 { pendingShot = nil } })) {
            PhotoCaptureView { image in
                if let image {
                    if pendingShot == .front { frontImage = image } else { backImage = image }
                }
                pendingShot = nil
            }
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            BackButton(action: onClose)
            Text("Add food").font(.milo(19, .heavy)).foregroundStyle(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Theme.bg)
    }

    private var segmented: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { m in
                Text(m.rawValue)
                    .font(.milo(13, .heavy))
                    .foregroundStyle(mode == m ? Theme.brandDeep : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(mode == m ? Theme.card : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: mode == m ? Theme.brandDeep.opacity(0.15) : .clear, radius: 6, y: 3)
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { mode = m; notice = nil } }
            }
        }
        .padding(5)
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20).padding(.top, 8)
    }

    // MARK: Package — guided two-shot

    private var packagePanel: some View {
        VStack(spacing: 0) {
            shotCard(title: "Front of the bag",
                     subtitle: "Name and brand",
                     image: frontImage, icon: "🥡") { pendingShot = .front }
            shotCard(title: "Nutrition label",
                     subtitle: "Guaranteed analysis + ingredients",
                     image: backImage, icon: "🏷️") { pendingShot = .back }

            Text(PhotoCaptureView.hasCamera
                 ? "Snap both sides in either order — the AI reads them together and drafts the entry for you to check."
                 : "No camera here — pick label photos from the library instead.")
                .captionStyle()

            noticeView

            PrimaryButton(title: "Read the label",
                          systemImage: "sparkles",
                          enabled: frontImage != nil && backImage != nil) {
                handlePackage()
            }
            .padding(.horizontal, 20).padding(.top, 18)
        }
    }

    private func shotCard(title: String, subtitle: String, image: UIImage?,
                          icon: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                ZStack {
                    if let image {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        Text(icon).font(.system(size: 26))
                            .frame(width: 62, height: 62)
                            .background(Theme.track)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if image != nil {
                        Circle().fill(Theme.brand).frame(width: 22, height: 22)
                            .overlay(Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                            .offset(x: 24, y: -24)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.milo(15, .heavy)).foregroundStyle(Theme.ink)
                    Text(image == nil ? subtitle : "Tap to retake")
                        .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "camera.fill").font(.system(size: 16)).foregroundStyle(Theme.brand)
            }
            .padding(15)
            .miloCard(radius: 20, padding: 0)
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 20).padding(.top, 12)
    }

    private func handlePackage() {
        guard let frontImage, backImage != nil, !busy else { return }
        busy = true; busyLabel = "Reading the label…"; notice = nil
        Task {
            defer { busy = false }
            let draft = await FoodAI.draftPackagedProduct(front: frontImage, back: backImage)
            if !draft.usedAI {
                notice = "On-device AI isn't available here — drafted from the label text; check every field."
            }
            model.prepare(product: draft.product, dogs: store.dogs, fromAIDraft: true)
            path.append(.confirm)
        }
    }

    // MARK: Fresh — pick foods Milo knows, one estimate pass on continue

    private var naturalPanel: some View {
        VStack(spacing: 0) {
            FreshFoodComposer { inputs in
                handleNaturalMeal(inputs)
            }
            noticeView
        }
    }

    private func handleNaturalMeal(_ inputs: [FoodAI.MealItemInput]) {
        guard !busy, !inputs.isEmpty else { return }
        busy = true; busyLabel = "Working out the numbers…"; notice = nil
        Task {
            defer { busy = false }
            let products = await FoodAI.estimateMeal(inputs)
            guard !products.isEmpty else {
                notice = "Add at least one food."
                return
            }
            if products.contains(where: { $0.kcalPerUnit == 0 }) {
                notice = "A food couldn't be estimated — fill its calories on the next screen."
            }
            model.prepareMeal(products, dogs: store.dogs)
            path.append(.confirm)
        }
    }

    @ViewBuilder private var noticeView: some View {
        if let notice {
            Text(notice)
                .font(.milo(12.5, .bold))
                .foregroundStyle(Color(hex: 0xB4562E))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 10)
        }
    }

    // MARK: Manual

    private var manualPanel: some View {
        VStack(spacing: 0) {
            // Primary: type in a new food's nutrition details yourself.
            Button { path.append(.manualForm) } label: {
                HStack(spacing: 13) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 19))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(Theme.brandGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Add a food manually").font(.milo(15, .heavy)).foregroundStyle(Theme.ink)
                        Text("Type in the name, calories and ingredients yourself")
                            .font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.milo(15, .heavy)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 15).padding(.vertical, 13)
                .miloCard(radius: Theme.rPill, padding: 0)
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)

            HStack {
                Text("YOUR FAVOURITES").font(.milo(12, .heavy)).foregroundStyle(Theme.muted)
                Spacer()
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)

            ForEach(store.favorites) { fav in
                FavoriteRow(product: fav) {
                    model.prepare(product: fav, dogs: store.dogs, fromAIDraft: false)
                    path.append(.assign)
                }
            }
            Text("Quick-log the things you feed every day in one tap — honest preset portions, no AI needed.")
                .captionStyle()
        }
    }
}

// MARK: - Favorite row

struct FavoriteRow: View {
    var product: Product
    var onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 13) {
                Text(product.emoji).font(.system(size: 21))
                    .frame(width: 42, height: 42)
                    .background(Theme.track)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(product.name).font(.milo(14.5, .heavy)).foregroundStyle(Theme.ink)
                        if product.ingredients.contains(where: { $0.contains("chicken") }) {
                            Chip(text: "chicken", icon: "⚠", kind: .warn)
                        }
                    }
                    Text(favSubtitle).font(.milo(11.5, .bold)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Text("＋").font(.milo(20, .heavy)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Theme.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .miloCard(radius: 18, padding: 0)
        }
        .buttonStyle(PressStyle())
        .padding(.horizontal, 20).padding(.bottom, 10)
    }

    private var favSubtitle: String {
        let kcal = product.isEstimate ? "~\(product.kcalPerUnit)" : "\(product.kcalPerUnit)"
        return "\(product.portionBasis) · \(kcal) kcal · \(product.category.label.lowercased())"
    }
}

private extension Text {
    func captionStyle() -> some View {
        self.font(.milo(12, .bold))
            .foregroundStyle(Theme.muted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24).padding(.top, 16)
    }
}
