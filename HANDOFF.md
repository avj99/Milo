# Milo — Engineering Handoff

_Last updated: 2026-07-22_

Milo is a native iOS (SwiftUI) app that helps households track everything their
dogs eat — meals, treats, human add-ins — to manage calories and catch
allergens. Camera-first in concept; AI drafts an entry, the owner confirms.
Deliberately **not** medical/veterinary — it tracks intake and flags
"discuss with your vet."

- **Repo:** `~/Documents/Milo` (git initialised; **not yet pushed to GitHub** — see Pending)
- **Xcode project:** `Milo.xcodeproj` — Xcode 26.6, SwiftUI, iOS 17 deployment target, bundle id `com.milo.app`, objectVersion 77 (synchronized folder groups, so new files under `Milo/` are auto-included).
- **Supabase project:** `Milo`, ref **`lxkjhflvxrygtzmjrhqh`**, org TrustPacketAI, us-east-1. Dashboard: https://supabase.com/dashboard/project/lxkjhflvxrygtzmjrhqh

---

## 1. How to build & run

```bash
# Build to a DerivedData path OUTSIDE ~/Documents (see gotcha below)
DD=/tmp/milo-dd
xcodebuild -project Milo.xcodeproj -scheme Milo \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=<sim>' \
  -configuration Debug -derivedDataPath "$DD" build
```

**Gotchas (important):**
- **Codesign "resource fork / detritus" error when building under `~/Documents`:** macOS stamps provenance xattrs on files there, which breaks the ad-hoc codesign. Fix: build with `-derivedDataPath` pointing outside `~/Documents` (e.g. `/tmp/...`), and/or `xattr -cr .` before building.
- **Sign in with Apple entitlement builds fine on the simulator** under ad-hoc "Sign to Run Locally" — no provisioning profile needed for simulator. Device builds will need a real Apple Developer team.
- **Simulator runtime:** iOS 26.5 runtime is installed; sim device used during dev was `Milo-iPhone16` (iPhone 16 Pro).

**Debug launch hooks (DEBUG builds only, via `SIMCTL_CHILD_*` env):**
- `MILO_SCREEN=onboarding` — force the onboarding flow.
- `MILO_OB_STEP=<0–11>` — jump to an onboarding step with sample data.
- `MILO_OB_FOCUS=dog|hh` — focus a text field (keyboard testing).
- `MILO_OB_AGE=<months>` — set age to test the puppy calorie path.

---

## 2. File map

```
Milo/
  MiloApp.swift            App entry + AppGate (onboarding vs main app)
  Theme.swift              Design tokens (colors, type, radii) from the mockup
  Models.swift             Household → Member → Dog → Product → LogEntry (all Codable)
  Engine.swift             CalorieEngine (RER/MER + NRC puppy) + AllergenEngine
  BreedCatalog.swift       ~65-breed reference table (size + ideal weight ranges)
  Store.swift              AppStore (in-app state) + local JSON persistence
  Milo.entitlements        Sign in with Apple capability
  Assets.xcassets          AppIcon (dog+bowl logo), AccentColor, MiloLogo
  Views/
    RootView.swift         Tab bar + FAB + toast + nav
    HomeView.swift         Dog list
    DashboardView.swift    Calorie ring, live activity, today's log
    HouseholdView.swift    Members, invite code
    CaptureFlow.swift      Scan/Photo/Manual capture coordinator
    ConfirmView.swift      Confirm the AI/typed draft
    AssignView.swift       Assign-to-dogs + per-dog allergen check
    ManualEntryView.swift  Type in a food's nutrition
    OnboardingView.swift   12-step first-run flow (SwiftUI port of the DC design)
    OnboardingModel.swift  Onboarding state + mapping to Dog
    Components.swift        Shared UI (chips, rings, buttons, flow layout)
  Supabase/
    SupabaseConfig.swift   Project URL + publishable key
    SupabaseService.swift  Client, DTOs, auth, queries, realtime (#if canImport(Supabase))
    AppleSignIn.swift       ASAuthorizationController coordinator (nonce + SHA256)
    README-supabase.md      SDK/auth setup steps
supabase/migrations/       0001 schema, 0002 RLS, 0003 RPCs + realtime (SQL)
```

---

## 3. What's DONE (in detail)

### 3.1 App shell, design & navigation
- Full native SwiftUI port of the mockup + the Claude Design onboarding file
  (`Milo Onboarding.dc.html`). Design tokens centralized in `Theme.swift`.
- Screens implemented & simulator-verified: Home, Dog Dashboard (calorie ring +
  live "fed by" strip + today's log), Capture (Scan/Photo/Manual), Confirm,
  Assign (per-dog portions + per-dog allergen flag + toast), Household, and the
  12-step Onboarding.
- **App icon** = the dog + bowl "Milo" logo (cream tile), set as `AppIcon` and
  shown on the onboarding welcome; verified on the iOS home screen.

### 3.2 Onboarding (12 steps)
Welcome → Household (name / invite code) → Add dog → Breed → Basics
(age/sex/neuter) → Weight (drag ruler) → Body condition (BCS) → Activity →
Allergens → animated calorie **Reveal** → Invite → Done.
- Renders one step at a time with a fade transition (an earlier HStack-track
  approach bled overflow across screens — avoid it).
- **Keyboard handling fixed**: the primary button rides above the keyboard via a
  bottom `safeAreaInset` and the focused field scrolls into view (the whole
  screen is NOT wrapped in a GeometryReader, which would trap the button behind
  the keyboard). Return key advances.
- On "Start using Milo" it writes a real household + dog to the store; the gate
  (`AppGate`) flips to the main app when `store.isSetUp` (household != nil).

### 3.3 Data model & persistence
- `Household → Member → Dog → Product → LogEntry`, all `Codable`.
  `Dog.avatar` is `[UInt]` hex (so it encodes), `Dog.ageMonths` (month
  granularity for puppies), `Dog.targetOverride` (frozen reveal number).
- **No placeholder/sample data.** The app starts empty and holds only what the
  user adds. State persists locally as JSON at
  `Library/Application Support/milo_store.json` (`LocalStore`), surviving
  relaunches with no backend. Logged foods accumulate into favourites.
- Verified: injecting a synthetic snapshot renders correctly on Home.

### 3.4 Calorie engine & breed data (peer-reviewed) — see §5 for sources
- `BreedCatalog.swift`: ~65 common breeds → size class + typical adult weight
  range. Selecting a breed pre-loads the weight ruler to the breed midpoint.
  Searchable. Mixed/unknown falls back to size class.
- `CalorieEngine`:
  - **RER** = 70·kg^0.75.
  - **Adult** (age ≥ breed maturity): MER = RER(ideal weight) × life-stage
    factor (neutered 1.6 / intact 1.8 / active 2.0 / senior 1.3), clamped down
    for overweight (≤1.4) / obese (≤1.2). Ideal weight = BCS-adjusted current
    weight (BCS weighted over breed).
  - **Puppy** (still growing): NRC 2006 growth equation
    `130·kg^0.75·3.2·(e^(−0.87·p)−0.1)`, p = current ÷ expected-adult (breed
    midpoint). Uses current weight.
  - Returns `CalorieResult` with `method` + `caveats[]`. UI shows a "🐾 Growing
    puppy" chip + age-appropriate safety copy; dashboard disclaimer is
    puppy-aware.
  - Verified numbers: adult 30.5 kg Lab → 1,450 kcal; 4-mo 12 kg Lab pup →
    1,640 kcal (an adult formula would underfeed the pup at ~1,030).

### 3.5 Allergen engine
- `AllergenEngine` normalizes an ingredient list to canonical allergens via a
  surface→canonical synonym map (e.g. "chicken meal"/"poultry fat" → chicken)
  and flags **per dog** at assign time (one treat → three dogs flags only the
  one that reacts). Non-medical framing.

### 3.6 Auth
- **Sign in with Apple**: `AppleSignIn.swift` (async `ASAuthorizationController`
  with random nonce + SHA256, returns idToken + raw nonce + name). Wired on the
  welcome screen; on success adopts the Apple display name and calls Supabase
  `signInWithIdToken`. Entitlement present and builds on simulator.
- **Email + password**: `SupabaseService.signIn/signUp`; welcome has a
  "Continue with email" sheet (create account / sign in). Code is complete and
  builds. **NOTE:** the Email provider is currently **disabled** on the Supabase
  project, so it won't authenticate until enabled (see Pending).

### 3.7 Supabase backend
- Schema/RLS/RPCs/realtime applied to `lxkjhflvxrygtzmjrhqh` (also saved as SQL
  in `supabase/migrations/`):
  - Tables: `households, members, dogs, dog_allergens, products, log_entries`.
  - **RLS on every table** — household isolation via `user_households()`
    SECURITY DEFINER helper.
  - RPCs `create_household(name, member_name)` and `join_household(code,
    member_name)` (SECURITY DEFINER, gated on `auth.uid()`).
  - Realtime publication includes `log_entries, dogs, members`.
  - Verified: 0 rows in all tables (clean DB, no seed data).
- **iOS client SDK integrated**: `supabase-swift` 2.53.0 added via SPM (package
  refs written into the pbxproj + resolved). `SupabaseService` (DTOs, auth,
  household/dog/log queries, realtime channel) compiles against the real SDK and
  the app builds/runs with it linked. Still behind `#if canImport(Supabase)`.

### 3.8 Git
- Repo initialised; `.gitignore` excludes build output/DerivedData. Commits:
  `Initial commit` → `email auth + Supabase SDK` → `breed catalog + calorie
  engine`.

---

## 4. What's PENDING

**Backend / auth (blocking real cloud sync):**
1. **Enable the Email provider** in Supabase → Auth → Sign In / Providers, and
   turn **"Confirm email" OFF** for instant dev signups. (Currently email is
   off, so "Continue with email" will error.)
2. **Configure the Apple provider** in Supabase (Service ID + key) for the Apple
   sign-in round-trip to authenticate. Needs a paid Apple Developer account.
3. **`SupabaseStore` adapter** — the app still reads/writes **local** JSON; the
   Supabase client is linked but not yet the source of truth. Build an adapter
   that maps DTOs ↔ `Dog`/`LogEntry`, does live reads/writes, and subscribes to
   realtime, with local as an offline cache. (Steps in
   `Milo/Supabase/README-supabase.md`.)

**Distribution:**
4. **Push to GitHub** — `gh` CLI is not installed. Either `brew install gh &&
   gh auth login` then `gh repo create`, or create an empty repo and
   `git remote add origin … && git push -u origin main`.
5. **Real signing/provisioning** for device builds + TestFlight (Apple Developer
   team, App IDs, capabilities).

**Product (Phase 2+ from the build guide):**
6. **Camera capture pipeline** — currently Scan/Photo produce a hardcoded demo
   draft. Real work: VisionKit barcode scan, Apple Vision OCR, cloud AI vision
   (photo → structured product draft + ingredient normalization).
7. **Crowdsourced product database** — unverified→verified gate, moderation
   queue, report/flag control (Apple UGC guideline 1.2), seed from Open Pet Food
   Facts.
8. **Multi-dog + household realtime** — add-another-dog UI, invite/join over the
   backend (join is a local stub today), live "fed by Mom, 4 min ago" via the
   realtime channel.
9. **Trends screen** (tab exists, not built), account deletion (App Store req),
   privacy nutrition labels, "Data sources & licenses" screen.
10. **Breed catalog depth** — expand beyond ~65 breeds; consider sex-specific
    ranges; "recalculate as your puppy grows" reminders.

**Housekeeping:**
11. Remove/gate off the DEBUG launch hooks before release. Move the Supabase
    publishable key to an xcconfig if preferred (it's public/safe to ship as-is).

---

## 5. Sources & method (nutrition data, weights, formulas)

All calorie math and weight references are grounded in peer-reviewed / veterinary
consensus sources. Raw factual weight ranges are not copyrightable, so the breed
table is compiled and owned outright (safe for commercial use).

**Energy requirement equations (calorie targets):**
- **National Research Council (NRC), 2006 — _Nutrient Requirements of Dogs and
  Cats_.** The authoritative source. Adult MER allometric equations and the
  puppy growth equation `130·BW^0.75·3.2·(e^(−0.87·p)−0.1)`.
- **FEDIAF — Nutritional Guidelines for Complete and Complementary Pet Food for
  Cats and Dogs.** Evidence-based MER factors by life stage.
- **Merck Veterinary Manual — Nutritional Requirements of Small Animals** (RER =
  70·kg^0.75; MER = RER × life-stage factor):
  https://www.merckvetmanual.com/management-and-nutrition/nutrition-small-animals/nutritional-requirements-of-small-animals
- **Association for Pet Obesity Prevention (APOP)** — RER/MER calculator +
  guidance: https://www.petobesityprevention.org
- Pedrinelli et al. (2021), _Predictive equations of maintenance energy
  requirement for healthy and chronically ill adult dogs_, J. Anim. Physiol.
  Anim. Nutr.: https://onlinelibrary.wiley.com/doi/10.1111/jpn.13184
- Puppy growth energy (NRC eq. summary):
  https://ga-petfoodpartners.co.uk/knowledge-centre/energy-requirements-of-puppies/

**Breed ideal-weight ranges & size classes:**
- **APOP — Ideal Dog & Cat Weights by Breed:**
  https://www.petobesityprevention.org/ideal-weight-ranges
- Public breed standards: **AKC** (akc.org), **FCI**, **The Kennel Club** — used
  as factual references for typical adult weight ranges and size class.
- Body Condition Score: the 9-point WSAVA/Purina BCS is the clinical standard we
  treat as a first-class, individual signal (more reliable than breed).

**Product / food nutrition data (for later, Phase 2):**
- **Open Pet Food Facts** (data ODbL, contents DbCL, images CC-BY-SA) — sparse
  pet-food catalogue; attribution + share-alike required:
  https://world.openpetfoodfacts.org/data
- **The Dog API** (thedogapi.com) — breed weight ranges; free tier requires
  "The Dog API" attribution.

**Framing:** every calorie number is presented as an estimate ("individual dogs
vary 20%+"), never a prescription; puppies and overweight dogs get explicit
"confirm with your vet" caveats. Milo is intake tracking + flags, not veterinary
advice.

---

## 6. Key decisions & rationale
- **Local-first persistence now, Supabase later:** the app is fully functional
  offline; the cloud layer is linked and ready but not yet the source of truth,
  so nothing blocks on backend config while iterating.
- **BCS over breed for ideal weight:** breed gives a starting estimate; the
  individual's body-condition score refines it (per the build guide).
- **Puppy path is non-negotiable:** feeding a growing dog on an adult formula
  underfeeds it — the age-aware NRC growth equation prevents that.
- **Publishable Supabase key in-app is safe:** RLS protects data, not the key.
