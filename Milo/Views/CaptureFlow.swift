import SwiftUI

// The "capture once → assign to many" pipeline, presented as a modal flow:
//   Capture (Scan / Photo / Manual) → Confirm the AI draft → Assign to dogs.
// Manual quick-log skips Confirm and goes straight to Assign.

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

    /// Per-dog selection + portion, keyed by dog id.
    @Published var selection: [UUID: Bool] = [:]
    @Published var portions: [UUID: Int] = [:]

    func prepare(product: Product, dogs: [Dog], fromAIDraft: Bool) {
        self.product = product
        self.fromAIDraft = fromAIDraft
        for d in dogs {
            selection[d.id] = true
            portions[d.id] = 1
        }
    }
}

struct CaptureFlow: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = CaptureModel()
    @State private var path: [CaptureStep] = []

    /// Optional deep-link entry point (used for verification screenshots).
    var initialStep: CaptureStep? = nil

    /// The AI-drafted product produced by scan/photo (unverified, trips Bella's allergy).
    static let aiDraft = Product(
        name: "Chicken Jerky Bites", brand: "Happy Tails", emoji: "🍗",
        category: .treat, kcalPerUnit: 32, portionBasis: "piece",
        ingredients: ["chicken breast", "glycerin", "salt"], verified: false)

    var body: some View {
        NavigationStack(path: $path) {
            CaptureView(model: model, path: $path, onClose: { dismiss() })
                .navigationDestination(for: CaptureStep.self) { step in
                    switch step {
                    case .confirm:    ConfirmView(model: model, path: $path)
                    case .manualForm: ManualEntryView(model: model, path: $path)
                    case .assign:     AssignView(model: model, onDone: { dismiss() })
                    case .scan:       EmptyView()
                    }
                }
        }
        .environmentObject(model)
        .onAppear {
            if let step = initialStep, step != .scan {
                model.prepare(product: Self.aiDraft, dogs: store.dogs, fromAIDraft: true)
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

    enum Mode: String, CaseIterable { case scan = "Scan", photo = "Photo", manual = "Manual" }
    @State private var mode: Mode = .scan

    /// The AI-drafted product produced by scan/photo (unverified, trips Bella's allergy).
    private var draft: Product { CaptureFlow.aiDraft }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                segmented
                switch mode {
                case .scan:   scanPanel
                case .photo:  photoPanel
                case .manual: manualPanel
                }
                Spacer(minLength: 0)
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top) { topBar }
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
                    .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { mode = m } }
            }
        }
        .padding(5)
        .background(Theme.track)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 20).padding(.top, 8)
    }

    // Scan / Photo share a viewfinder + shutter that draft via AI.
    private var scanPanel: some View {
        VStack(spacing: 0) {
            Viewfinder(kind: .barcode)
            Text("The AI reads the label and drafts the entry — you just confirm it on the next screen.")
                .captionStyle()
            shutter
        }
    }

    private var photoPanel: some View {
        VStack(spacing: 0) {
            Viewfinder(kind: .label)
            Text("Not in the database? A photo lets the AI fill in the name, calories and ingredients.")
                .captionStyle()
            shutter
        }
    }

    private var shutter: some View {
        Button {
            model.prepare(product: draft, dogs: store.dogs, fromAIDraft: true)
            path.append(.confirm)
        } label: {
            Circle()
                .fill(.white)
                .frame(width: 70, height: 70)
                .overlay(Circle().strokeBorder(Theme.brand, lineWidth: 5))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 6)
        }
        .buttonStyle(PressStyle())
        .padding(.top, 18)
    }

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
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 6)

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

// MARK: - Viewfinder

struct Viewfinder: View {
    enum Kind { case barcode, label }
    var kind: Kind

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x20302A), Color(hex: 0x0F1A15)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            switch kind {
            case .barcode:
                VStack(spacing: 14) {
                    Text("▊▍▉▍▊▎▉▍▊").font(.system(size: 40))
                }
                frameCorners
                VStack {
                    Spacer()
                    Text("Line up the barcode on the bag or treat")
                        .font(.milo(12.5, .bold)).foregroundStyle(Color(hex: 0xDCE7E0))
                        .padding(.bottom, 20)
                }
            case .label:
                VStack(spacing: 10) {
                    Text("🏷️").font(.system(size: 48))
                    Text("Fit the nutrition panel in frame")
                        .font(.milo(12.5, .heavy)).foregroundStyle(Color(hex: 0xDCE7E0))
                }
                .frame(width: 240, height: 210)
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6])))
                VStack {
                    Spacer()
                    Text("A photo lets the AI fill it in")
                        .font(.milo(12, .bold)).foregroundStyle(Color(hex: 0xDCE7E0))
                        .padding(.bottom, 18)
                }
            }
        }
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 20).padding(.top, 4)
    }

    private var frameCorners: some View {
        RoundedRectangle(cornerRadius: 18)
            .strokeBorder(Theme.accent, lineWidth: 3)
            .frame(width: 210, height: 150)
            .opacity(0.9)
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
        let tag: String
        switch product.category {
        case .meal:  tag = "fed daily"
        case .treat: tag = "treat"
        case .addIn: tag = "human add-in"
        }
        return "\(product.portionBasis) · \(kcal) kcal · \(tag)"
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
