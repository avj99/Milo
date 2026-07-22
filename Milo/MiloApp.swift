import SwiftUI

@main
struct MiloApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            AppGate()
                .environmentObject(store)
                .tint(Theme.brand)
        }
    }
}

/// Shows onboarding until a household exists (real data the user created),
/// then the main app. Onboarding writes straight to the store, so the gate
/// flips automatically once setup completes.
struct AppGate: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        // A DEBUG deep-link can force the onboarding flow for screenshots.
        #if DEBUG
        let forceOnboarding = ProcessInfo.processInfo.environment["MILO_SCREEN"] == "onboarding"
        #else
        let forceOnboarding = false
        #endif

        Group {
            if store.isSetUp && !forceOnboarding {
                RootView()
            } else {
                OnboardingView()
            }
        }
    }
}
