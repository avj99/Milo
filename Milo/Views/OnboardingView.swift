import SwiftUI
import AuthenticationServices

/// Native SwiftUI implementation of "Milo Onboarding.dc.html".
/// A horizontally-sliding 12-step first-run flow with a top progress bar,
/// a bottom primary button, and an animated calorie-target reveal.
struct OnboardingView: View {
    /// Called on completion with the created dog (nil if the user joined an
    /// existing household without adding one here).
    @EnvironmentObject var store: AppStore

    @StateObject private var m = OnboardingModel()
    @FocusState private var focus: Field?
    private enum Field { case hhName, code, dogName, breed, allergen }

    @State private var revealProgress: Double = 0
    @State private var rulerStartV: Double? = nil
    @State private var spin = false
    @State private var screenW: CGFloat = UIScreen.main.bounds.width

    @StateObject private var apple = AppleSignInCoordinator()
    @State private var authError: String?

    private let muted2 = Color(hex: 0x98A29B)

    /// Runs Sign in with Apple, then advances into the flow. On success we adopt
    /// the Apple display name and (once the SDK is added) sign into Supabase.
    private func authenticate(_ mode: OnboardingModel.Mode) {
        authError = nil
        Task {
            do {
                let cred = try await apple.signIn()
                if let name = cred.fullName { store.updateCurrentUser(name: name) }
                #if canImport(Supabase)
                try? await SupabaseService.shared.signInWithApple(
                    idToken: cred.idToken, nonce: cred.rawNonce)
                #endif
                m.mode = mode
                m.go(1)
            } catch {
                // A user cancel is not an error worth surfacing.
                if (error as? ASAuthorizationError)?.code != .canceled {
                    authError = "Couldn't sign in with Apple. Please try again."
                }
            }
        }
    }

    var body: some View {
        // NB: no GeometryReader wrapping the whole screen — its frame doesn't
        // shrink for the keyboard, which would trap the bottom button behind it.
        // Width is measured via a background reader so normal keyboard avoidance
        // (and the safe-area-inset button riding above the keyboard) works.
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()

            currentStep(screenW)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(m.step)
                .transition(.opacity)
        }
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { screenW = g.size.width }
                    .onChange(of: g.size.width) { _, nw in screenW = nw }
            }
        )
        .overlay(alignment: .top) { if m.step >= 1 && m.step <= 10 { chrome } }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if m.step >= 1 && m.step <= 9 { bottomBar } else { Color.clear.frame(height: 0) }
        }
        .onChange(of: m.step) { _, s in
            if s == 9 { startReveal() }
        }
        .onAppear(perform: applyDebugStep)
    }

    @ViewBuilder
    private func currentStep(_ w: CGFloat) -> some View {
        switch m.step {
        case 0:  welcomeStep(w)
        case 1:  householdStep(w)
        case 2:  meetDogStep(w)
        case 3:  breedStep(w)
        case 4:  basicsStep(w)
        case 5:  weightStep(w)
        case 6:  bcsStep(w)
        case 7:  activityStep(w)
        case 8:  allergenStep(w)
        case 9:  revealStep(w)
        case 10: inviteStep(w)
        default: doneStep(w)
        }
    }

    /// DEBUG: jump straight to a step (with sample data) for verification shots.
    private func applyDebugStep() {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["MILO_OB_STEP"],
              let n = Int(raw) else { return }
        m.dogName = "Bella"
        m.breed = "Labrador Retriever"; m.breedSize = "Large · ~30 kg"
        m.allergens = ["Chicken"]
        let focusEnv = ProcessInfo.processInfo.environment["MILO_OB_FOCUS"]
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000)
            m.go(n)                       // animated → transition settles cleanly
            if n == 9 { startReveal() }
            if let f = focusEnv {
                try? await Task.sleep(nanoseconds: 700_000_000)
                switch f {
                case "dog": focus = .dogName
                case "hh":  focus = .hhName
                default:    break
                }
            }
        }
        #endif
    }

    // MARK: - Global chrome (progress + back)

    private var chrome: some View {
        HStack(spacing: 12) {
            Button(action: m.back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 32, height: 32)
            }
            Capsule().fill(Color(hex: 0x1B2B25, alpha: 0.1))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(Theme.brand)
                            .frame(width: g.size.width * m.progressPct / 100)
                            .animation(.timingCurve(0.42, 0, 0.15, 1, duration: 0.48), value: m.progressPct)
                    }
                }
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    // MARK: - Global primary button

    private var primaryLabel: String {
        (m.step == 1 && m.mode == .join) ? "Join household" : "Continue"
    }
    private var primaryDisabled: Bool {
        if m.step == 1 && m.mode == .join { return m.inviteCode.count < 6 }
        if m.step == 2 { return m.dogName.trimmingCharacters(in: .whitespaces).isEmpty }
        return false
    }
    private var skipInfo: (show: Bool, label: String) {
        if m.step == 3 { return (true, "Skip for now") }
        if m.step == 8 { return (true, "None for now") }
        return (false, "")
    }

    private var bottomBar: some View {
        VStack(spacing: 2) {
            if skipInfo.show {
                Button(skipInfo.label) { focus = nil; m.stepForward() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(height: 44)
            }
            Button {
                focus = nil; m.stepForward()
            } label: {
                Text(primaryLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(primaryDisabled ? Theme.muted : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(primaryDisabled ? Color(hex: 0xD8DED6) : Theme.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(PressStyle())
            .disabled(primaryDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            // Fade so scrolled content dissolves behind the button instead of
            // colliding with it.
            LinearGradient(stops: [
                .init(color: Theme.bg.opacity(0), location: 0),
                .init(color: Theme.bg, location: 0.4),
                .init(color: Theme.bg, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        )
    }

    // MARK: - Reusable pieces

    private func title(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t)
                .font(.system(size: 27, weight: .bold, design: .default))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(sub)
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepScroll<Content: View>(_ w: CGFloat, top: CGFloat = 84,
                                            @ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.top, top)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .scrollDismissesKeyboard(.interactively)
    }

    private func fieldCard(label: String, text: Binding<String>, field: Field,
                           placeholder: String, submitLabel: SubmitLabel = .done,
                           onSubmit: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            TextField(placeholder, text: text)
                .font(.system(size: 18))
                .foregroundStyle(Theme.ink)
                .focused($focus, equals: field)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
        }
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(focus == field ? Theme.brand : Color(hex: 0x1B2B25, alpha: 0.08), lineWidth: 1.5))
    }

    private func searchField(placeholder: String, text: Binding<String>, field: Field) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(muted2)
            TextField(placeholder, text: text)
                .font(.system(size: 16)).foregroundStyle(Theme.ink)
                .focused($focus, equals: field)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    // MARK: - 0 Welcome

    private func welcomeStep(_ w: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
            logo
            Text("Know exactly what your dogs eat.")
                .font(.system(size: 19)).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center).frame(maxWidth: 250)
                .padding(.top, 40)
            Spacer()
            VStack(spacing: 12) {
                Button { authenticate(.new) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "applelogo").font(.system(size: 18, weight: .medium))
                        Text("Sign in with Apple").font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(PressStyle())

                Button { authenticate(.join) } label: {
                    Text("I have an invite code").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.brand).frame(maxWidth: .infinity).frame(height: 56)
                }

                if let authError {
                    Text(authError).font(.system(size: 13)).foregroundStyle(Theme.alert)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(.horizontal, 30).padding(.top, 60).padding(.bottom, 40)
        .frame(maxWidth: .infinity)
    }

    private var logo: some View {
        ZStack {
            Circle().strokeBorder(Theme.brand.opacity(0.14), lineWidth: 2).frame(width: 224, height: 224)
            ZStack {
                ForEach(0..<9, id: \.self) { i in
                    Text("🐾").font(.system(size: 15))
                        .opacity(i % 2 == 0 ? 0.5 : 1)
                        .offset(y: -102)
                        .rotationEffect(.degrees(Double(i) / 9 * 360))
                }
            }
            .frame(width: 224, height: 224)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) { spin = true } }

            Image("MiloLogo")
                .resizable().scaledToFit()
                .frame(width: 164, height: 164)
                .clipShape(RoundedRectangle(cornerRadius: 37, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 37, style: .continuous)
                    .strokeBorder(Theme.brandDeep.opacity(0.08), lineWidth: 1))
                .shadow(color: Theme.brandDeep.opacity(0.35), radius: 18, y: 12)
        }
        .frame(width: 224, height: 224)
    }

    // MARK: - 1 Household

    private func householdStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            if m.mode == .new {
                title("Name your household", "Milo is shared, so everyone stays in sync. You can change this later.")
                    .padding(.bottom, 30)
                fieldCard(label: "Household name", text: $m.householdName, field: .hhName,
                          placeholder: "", submitLabel: .next,
                          onSubmit: { focus = nil; m.stepForward() })
                Text("e.g. \"The Carter household\"")
                    .font(.system(size: 13)).foregroundStyle(muted2)
                    .padding(.leading, 4).padding(.top, 16)
            } else {
                title("Enter your invite code", "Ask a household member for the 6-digit code from their Milo app.")
                    .padding(.bottom, 30)
                codeBoxes
                if m.inviteCode.count == 6 {
                    joinedHouseholdCard.padding(.top, 24)
                }
            }
        }
        .padding(.horizontal, 24)
    }

    private var codeBoxes: some View {
        ZStack {
            TextField("", text: Binding(
                get: { m.inviteCode },
                set: { m.inviteCode = String($0.filter(\.isNumber).prefix(6)) }))
                .keyboardType(.numberPad)
                .focused($focus, equals: .code)
                .foregroundStyle(.clear).tint(.clear)
                .accentColor(.clear)
            HStack(spacing: 9) {
                ForEach(0..<6, id: \.self) { i in
                    let chars = Array(m.inviteCode)
                    let filled = i < chars.count
                    let active = focus == .code && i == chars.count
                    Text(filled ? String(chars[i]) : "")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1 / 1.15, contentMode: .fit)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(active || filled ? Theme.brand : Color(hex: 0x1B2B25, alpha: 0.1), lineWidth: 1.5))
                }
            }
            .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onTapGesture { focus = .code }
    }

    private var joinedHouseholdCard: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Color(hex: 0xE8F0EC)).frame(width: 40, height: 40)
                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.brand)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("The Carter household").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                Text("3 members · 2 dogs").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 2 Meet your dog

    private func meetDogStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            title("Let's add your first dog", "A photo and a name to get started.")
                .padding(.bottom, 34)
            VStack(spacing: 26) {
                Button { m.dogPhoto.toggle() } label: {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            if m.dogPhoto {
                                Circle().fill(Theme.brandGradient)
                                Text("dog\nphoto").font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.9)).multilineTextAlignment(.center)
                            } else {
                                Circle().fill(Color(hex: 0xDCE6DE))
                                VStack(spacing: 8) {
                                    Image(systemName: "camera").font(.system(size: 30, weight: .light)).foregroundStyle(Theme.brand)
                                    Text("Add photo").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brand)
                                }
                            }
                        }
                        .frame(width: 150, height: 150).clipShape(Circle())
                        Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 38, height: 38).background(Theme.brand).clipShape(Circle())
                            .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 3))
                    }
                }
                .buttonStyle(PressStyle())
                fieldCard(label: "Dog's name", text: $m.dogName, field: .dogName, placeholder: "",
                          submitLabel: .next,
                          onSubmit: { if !m.dogName.trimmingCharacters(in: .whitespaces).isEmpty { focus = nil; m.stepForward() } })
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 3 Breed

    private func breedStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            title("What breed is \(m.dogDisplayName)?", "This fine-tunes the estimate. Mutts are first-class here.")
                .padding(.horizontal, 4).padding(.bottom, 20)
            searchField(placeholder: "Search breeds", text: $m.breedQuery, field: .breed)
                .padding(.bottom, 14)
            mixedBreedRow.padding(.bottom, 12)
            VStack(spacing: 0) {
                ForEach(Array(m.filteredBreeds.enumerated()), id: \.element.name) { idx, b in
                    Button { m.breed = b.name; m.breedSize = b.size } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(b.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                                Text(b.size).font(.system(size: 12)).foregroundStyle(muted2)
                            }
                            Spacer(minLength: 0)
                            if m.breed == b.name {
                                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.brand)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(m.breed == b.name ? Color(hex: 0xF1F6F2) : Theme.card)
                        .overlay(alignment: .top) { if idx > 0 { Divider().overlay(Color(hex: 0x1B2B25, alpha: 0.06)) } }
                    }
                }
            }
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 20)
    }

    private var mixedBreedRow: some View {
        let sel = m.breed == "Mixed / unknown"
        return Button { m.breed = "Mixed / unknown"; m.breedSize = "" } label: {
            HStack(spacing: 12) {
                Image(systemName: "shuffle").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.brand)
                    .frame(width: 38, height: 38).background(Color(hex: 0xE8F0EC))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mixed / unknown").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text("Perfectly fine — most dogs are").font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                if sel { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.brand) }
            }
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(sel ? Color(hex: 0xF1F6F2) : Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(sel ? Theme.brand : .clear, lineWidth: 1.5))
        }
    }

    // MARK: - 4 Basics

    private func basicsStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            title("A few basics", "Quick taps — these sharpen the calorie math.").padding(.bottom, 28)
            VStack(spacing: 0) {
                HStack {
                    Text("Age").font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    HStack(spacing: 16) {
                        roundStep("minus") { m.ageDown() }
                        Text(m.ageLabel).font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.ink).frame(minWidth: 78)
                        roundStep("plus") { m.ageUp() }
                    }
                }
                .padding(.vertical, 16)
                Divider().overlay(Color(hex: 0x1B2B25, alpha: 0.06))
                segRow(title: "Sex", left: "Female", right: "Male",
                       leftOn: m.sexFemale, setLeft: { m.sexFemale = true }, setRight: { m.sexFemale = false })
                Divider().overlay(Color(hex: 0x1B2B25, alpha: 0.06))
                segRow(title: m.neuterLabel, left: "Yes", right: "Not yet",
                       leftOn: m.neutered, setLeft: { m.neutered = true }, setRight: { m.neutered = false })
            }
            .padding(.horizontal, 20)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 24)
    }

    private func roundStep(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.brand)
                .frame(width: 34, height: 34).background(Theme.bg).clipShape(Circle())
        }
    }

    private func segRow(title: String, left: String, right: String, leftOn: Bool,
                        setLeft: @escaping () -> Void, setRight: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 16, weight: .medium)).foregroundStyle(Theme.ink)
            HStack(spacing: 0) {
                segButton(left, on: leftOn, action: setLeft)
                segButton(right, on: !leftOn, action: setRight)
            }
            .padding(3).background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(.vertical, 16)
    }

    private func segButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? Theme.ink : Theme.muted)
                .frame(maxWidth: .infinity).padding(.vertical, 9)
                .background(on ? Theme.card : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: on ? Color(hex: 0x1B2B25, alpha: 0.14) : .clear, radius: 2, y: 1)
        }
    }

    // MARK: - 5 Weight

    private func weightStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            title("How much does \(m.dogDisplayName) weigh?", "Drag the ruler. Best guess is fine — you can update it anytime.")
                .padding(.horizontal, 24)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(m.weightDisplay).font(.system(size: 84, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.brandDeep).monospacedDigit()
                Text(m.unitLabel).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity).padding(.top, 44).padding(.bottom, 6)
            HStack {
                Spacer()
                HStack(spacing: 0) {
                    unitButton("kg", on: m.unitKg) { m.unitKg = true }
                    unitButton("lb", on: !m.unitKg) { m.unitKg = false }
                }
                .padding(3).background(Color(hex: 0xE4E8E0)).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }
            .padding(.bottom, 30)
            ruler(w)
        }
    }

    private func unitButton(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(on ? Theme.ink : Theme.muted)
                .padding(.horizontal, 20).padding(.vertical, 6)
                .background(on ? Theme.card : .clear).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func ruler(_ w: CGFloat) -> some View {
        let ticks = Array(stride(from: 2.0, through: 80.0, by: 0.5))
        // Offset so the tick for the current weight sits under the centre marker.
        // (each 0.5 kg = 14 pt; the -7 centres within the 14 pt tick slot.)
        let offsetX = w / 2 - CGFloat(m.weightKg - 2) * 28 - 7

        return Color.clear
            .frame(width: w, height: 96)
            .overlay(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(Array(ticks.enumerated()), id: \.offset) { _, v in
                        let isInt = v.truncatingRemainder(dividingBy: 1) == 0
                        let is5 = isInt && Int(v) % 5 == 0
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(is5 ? Theme.muted : Color(hex: 0x6E7B74, alpha: 0.4))
                                .frame(width: 2, height: is5 ? 26 : (isInt ? 18 : 11))
                            if is5 {
                                Text("\(Int(v))").font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(muted2)
                            }
                        }
                        .frame(width: 14, alignment: .top)
                    }
                }
                .padding(.top, 8)
                .offset(x: offsetX)
                .animation(rulerStartV == nil ? .easeOut(duration: 0.15) : nil, value: m.weightKg)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent)
                    .frame(width: 3, height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.accent.opacity(0.15), lineWidth: 4))
                    .offset(y: -12)
            }
            .overlay(alignment: .leading) {
                LinearGradient(colors: [Theme.bg, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 70)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
                LinearGradient(colors: [.clear, Theme.bg], startPoint: .leading, endPoint: .trailing).frame(width: 70)
                    .allowsHitTesting(false)
            }
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if rulerStartV == nil { rulerStartV = m.weightKg }
                        m.setWeight((rulerStartV ?? m.weightKg) - g.translation.width / 28)
                    }
                    .onEnded { _ in rulerStartV = nil }
            )
    }

    // MARK: - 6 Body condition

    private func bcsStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            title("Body condition", "Look at \(m.dogDisplayName) from the side. Which shape is closest?")
                .padding(.horizontal, 24).padding(.bottom, 24)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(m.bcsInfo.enumerated()), id: \.offset) { i, c in
                            bcsCard(i, c).id(i)
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 4)
                }
                .onChange(of: m.bcs) { _, v in withAnimation { proxy.scrollTo(v, anchor: .center) } }
                .onAppear { proxy.scrollTo(m.bcs, anchor: .center) }
            }
            let cur = m.bcsInfo[m.bcs]
            VStack(alignment: .leading, spacing: 5) {
                Text(cur.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.brand)
                Text(cur.desc).font(.system(size: 14)).foregroundStyle(Color(hex: 0x4A5751))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(.horizontal, 20).padding(.vertical, 18)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 24).padding(.top, 20)
        }
    }

    private func bcsCard(_ i: Int, _ c: OnboardingModel.BCSInfo) -> some View {
        let sel = m.bcs == i
        return Button { m.bcs = i } label: {
            VStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(Color(hex: 0xE8ECE4))
                    ZStack {
                        Ellipse().strokeBorder(Theme.brand.opacity(0.8), lineWidth: 2.5)
                            .frame(width: c.rx * 1.6, height: c.ry * 1.7)
                        Circle().strokeBorder(Theme.brand.opacity(0.8), lineWidth: 2.5)
                            .frame(width: 20, height: 20)
                            .offset(x: -(c.rx * 0.8) + 4, y: -10)
                    }
                    VStack { Spacer()
                        Text("side-profile · \(c.tag)").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted2)
                            .padding(.bottom, 7)
                    }
                }
                .frame(width: 122, height: 120).clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text(c.label).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(sel ? Theme.brand : Theme.ink)
            }
            .padding(14).frame(width: 150)
            .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(sel ? Theme.brand : .clear, lineWidth: 2))
            .scaleEffect(sel ? 1 : 0.96)
        }
    }

    // MARK: - 7 Activity

    private func activityStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            title("How active is \(m.dogDisplayName)?", "On a typical day.").padding(.bottom, 26)
            VStack(spacing: 13) {
                ForEach(Array(m.acts.enumerated()), id: \.offset) { i, a in
                    let sel = m.activity == i
                    Button { m.activity = i } label: {
                        HStack(spacing: 16) {
                            HStack(alignment: .bottom, spacing: 3) {
                                ForEach(0..<3, id: \.self) { b in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(a.bars >= b + 1 ? Theme.brand : Color(hex: 0xC7D0CA))
                                        .frame(width: 6, height: [9, 16, 23][b])
                                }
                            }
                            .frame(width: 48, height: 48).padding(12)
                            .background(sel ? Color(hex: 0xE8F0EC) : Color(hex: 0xF2F5F0))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.label).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                                Text(a.desc).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                            Spacer(minLength: 0)
                            if sel {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 26, height: 26).background(Theme.brand).clipShape(Circle())
                            }
                        }
                        .padding(18)
                        .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(sel ? Theme.brand : .clear, lineWidth: 2))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 8 Allergens

    private func allergenStep(_ w: CGFloat) -> some View {
        stepScroll(w, top: 96) {
            title("Anything to watch for?", "Add known allergens or sensitivities. You can set severity later.")
                .padding(.bottom, 22)
            if !m.allergens.isEmpty {
                FlowLayout(spacing: 9) {
                    ForEach(m.allergens, id: \.self) { a in
                        Button { m.toggleAllergen(a) } label: {
                            HStack(spacing: 7) {
                                Text(a).font(.system(size: 14, weight: .semibold))
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.leading, 15).padding(.trailing, 12).padding(.vertical, 9)
                            .background(Theme.alert).clipShape(Capsule())
                        }
                    }
                }
                .padding(.bottom, 16)
            }
            searchField(placeholder: "Search allergens", text: $m.allergenQuery, field: .allergen)
                .padding(.bottom, 18)
            Text("COMMON").font(.system(size: 12, weight: .semibold)).foregroundStyle(muted2)
                .kerning(0.4).padding(.bottom, 12)
            FlowLayout(spacing: 9) {
                ForEach(m.suggestedAllergens, id: \.self) { a in
                    Button { m.toggleAllergen(a) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(muted2)
                            Text(a).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.ink)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Theme.card).clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(Color(hex: 0x1B2B25, alpha: 0.12), lineWidth: 1.5))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - 9 Reveal

    private func revealStep(_ w: CGFloat) -> some View {
        let target = m.targetKcal()
        let shown = Int((Double(target) * revealProgress / 10).rounded()) * 10
        return VStack(spacing: 0) {
            Text("\(m.dogDisplayName)'s daily target".uppercased())
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xB98526))
                .kerning(1).frame(maxWidth: .infinity)
            Spacer()
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.16), lineWidth: 22)
                Circle().trim(from: 0, to: revealProgress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 4) {
                    Text(shown.formatted()).font(.system(size: 62, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.brandDeep).monospacedDigit()
                    Text("kcal / day").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 250, height: 250)
            Spacer()
            Text("An estimate to start from — you can fine-tune it anytime as you learn what keeps \(m.dogDisplayName) at their best.")
                .font(.system(size: 16)).foregroundStyle(Color(hex: 0x4A5751))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle").font(.system(size: 15)).foregroundStyle(Theme.brand)
                Text("Milo flags things worth discussing with your vet — it doesn't give medical advice.")
                    .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x4A5751))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 15).padding(.vertical, 13)
            .background(Theme.brand.opacity(0.07)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 28).padding(.top, 90).padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(colors: [Color(hex: 0xF6F0E4), Theme.bg], center: .init(x: 0.5, y: 0.22),
                           startRadius: 0, endRadius: 420).ignoresSafeArea())
    }

    // MARK: - 10 Invite

    private func inviteStep(_ w: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                title("Invite the household", "Milo works best when everyone logs meals and treats. Share this code to add family.")
                    .padding(.bottom, 30)
                VStack(spacing: 4) {
                    Text("HOUSEHOLD CODE").font(.system(size: 12, weight: .semibold)).foregroundStyle(muted2).kerning(0.5)
                    Text("4B29K7").font(.system(size: 40, weight: .bold, design: .rounded)).foregroundStyle(Theme.brandDeep).kerning(6)
                        .padding(.top, 12)
                    Text("milo.app/j/4B29K7").font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.top, 4)
                }
                .frame(maxWidth: .infinity).padding(26)
                .background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "eye").font(.system(size: 15)).foregroundStyle(Theme.brand)
                    (Text("Got a sitter or walker? Send them a ")
                     + Text("view-only link").foregroundColor(Theme.brand).bold()
                     + Text(" instead — they can log walks without seeing everything."))
                        .font(.system(size: 13)).foregroundStyle(Color(hex: 0x4A5751))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 15).padding(.vertical, 13).padding(.top, 16)
                .background(Theme.brand.opacity(0.06)).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer()
            VStack(spacing: 12) {
                Button { m.go(11) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share invite")
                    }
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Theme.brand).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(PressStyle())
                Button { m.go(11) } label: {
                    Text("Skip — I'll do this later").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).frame(height: 52)
                }
            }
        }
        .padding(.horizontal, 28).padding(.top, 96).padding(.bottom, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 11 Done

    private func doneStep(_ w: CGFloat) -> some View {
        let target = m.targetKcal()
        return ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Image(systemName: "checkmark").font(.system(size: 30, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 72, height: 72).background(Theme.brand).clipShape(Circle())
                        .shadow(color: Theme.brandDeep.opacity(0.5), radius: 12, y: 10)
                        .padding(.bottom, 16)
                    Text("\(m.dogDisplayName)'s all set 🐾").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.ink)
                    Text("Here's their home base.").font(.system(size: 15)).foregroundStyle(Theme.muted).padding(.top, 8)
                }
                .frame(maxWidth: .infinity).padding(.bottom, 26)

                VStack(spacing: 12) {
                    HStack(spacing: 13) {
                        Circle().fill(Theme.brandGradient).frame(width: 52, height: 52)
                            .overlay(Text("dog\nphoto").font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.dogDisplayName).font(.system(size: 19, weight: .bold)).foregroundStyle(Theme.ink)
                            Text(dashSub).font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().stroke(Theme.accent.opacity(0.2), lineWidth: 7)
                            Circle().trim(from: 0, to: 0.45).stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text("45%").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.brandDeep)
                        }
                        .frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Today's meals").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                            Text("\(Int(Double(target) * 0.45 / 10) * 10) of \(target.formatted()) kcal logged")
                                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16).background(Color(hex: 0xFBF6EC)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    HStack(spacing: 10) {
                        miniStat("Next meal", "6:00 PM")
                        miniStat("Treats left", "120 kcal")
                    }
                }
                .padding(20).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(hex: 0x1B2B25, alpha: 0.1), radius: 12, y: 6)

                Button {
                    if m.mode == .join { store.joinHousehold(code: m.inviteCode) }
                    else { store.createHousehold(name: m.householdName) }
                    store.addOnboardedDog(m.buildDog())
                } label: {
                    Text("Start using Milo").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Theme.brand).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(PressStyle()).padding(.top, 24)
                Button { revealProgress = 0; m.reset() } label: {
                    Text("↺ Replay onboarding").font(.system(size: 13, weight: .medium)).foregroundStyle(muted2)
                        .frame(maxWidth: .infinity).frame(height: 44)
                }.padding(.top, 8)
            }
            .padding(.horizontal, 22).padding(.top, 96).padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0xE9F0EB), Theme.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
    }

    private var dashSub: String {
        let breed = m.breed ?? "Mixed breed"
        return "\(breed) · \(Int(m.weightKg)) kg"
    }

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Reveal animation

    private func startReveal() {
        revealProgress = 0
        let start = Date()
        let duration = 1.7
        Task { @MainActor in
            while true {
                let t = Date().timeIntervalSince(start) / duration
                if t >= 1 { revealProgress = 1; break }
                revealProgress = 1 - pow(1 - t, 3)   // easeOutCubic
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
}

// MARK: - Flow layout for wrapping chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 9

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
