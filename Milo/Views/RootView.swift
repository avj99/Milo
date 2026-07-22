import SwiftUI

/// Navigation destinations pushed onto the home stack.
enum Route: Hashable {
    case dashboard(UUID)
    case household
}

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var path: [Route] = []
    @State private var captureItem: CaptureStep?

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationStack(path: $path) {
                HomeView(path: $path)
                    .navigationDestination(for: Route.self) { route in
                        switch route {
                        case .dashboard(let id): DashboardView(dogID: id, path: $path)
                        case .household:         HouseholdView()
                        }
                    }
            }

            TabBar(onAdd: { captureItem = .scan })
        }
        .fullScreenCover(item: $captureItem) { step in
            CaptureFlow(initialStep: step)
        }
        .onAppear(perform: applyDebugDeepLink)
        .overlay(alignment: .top) {
            if let toast = store.toast {
                ToastView(text: toast)
                    .padding(.top, 8)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.toast)
    }

    // MARK: - Debug screenshot deep-link
    // Reads MILO_SCREEN at launch so each screen can be captured in isolation
    // during verification. No effect in release builds or normal use.
    private func applyDebugDeepLink() {
        #if DEBUG
        guard let screen = ProcessInfo.processInfo.environment["MILO_SCREEN"] else { return }
        switch screen {
        case "dashboard":
            if let first = store.dogs.first { path = [.dashboard(first.id)] }
        case "household":
            path = [.household]
        case "capture":
            captureItem = .scan
        case "manualform":
            captureItem = .manualForm
        case "confirm":
            captureItem = .confirm
        case "assign":
            captureItem = .assign
        default:
            break
        }
        #endif
    }
}

// MARK: - Bottom tab bar with the central FAB

struct TabBar: View {
    var onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            tab(icon: "house.fill", label: "Home", on: true)
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Theme.brandGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Theme.bg, lineWidth: 4))
                    .shadow(color: Theme.brandDeep.opacity(0.5), radius: 13, y: 8)
            }
            .buttonStyle(PressStyle())
            .offset(y: -16)
            Spacer()
            tab(icon: "chart.bar.fill", label: "Trends", on: false)
        }
        .padding(.horizontal, 44)
        .padding(.top, 14)
        .frame(height: 92, alignment: .top)
        .background(
            LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg],
                           startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
        )
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .bottom)
    }

    private func tab(icon: String, label: String, on: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 20))
            Text(label).font(.milo(10, .heavy))
        }
        .foregroundStyle(on ? Theme.brand : Theme.muted)
        .frame(width: 60)
    }
}
