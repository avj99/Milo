# Milo — Engineering Handoff

_Last updated: 2026-07-31_

Milo is a native iOS (SwiftUI) app that helps households track everything their
dogs eat — meals, treats, human add-ins — to manage calories and catch
allergens. Camera-first in concept; AI drafts an entry, the owner confirms.
Deliberately **not** medical/veterinary — it tracks intake and flags
"discuss with your vet."

- **Repo:** `~/Documents/Documents - Avnish’s MacBook Air/Milo` — pushed to **github.com/avj99/Milo** (SSH remote, branch `master`)
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
    RootView.swift         Tab bar (Home · Fridge · FAB · Trends) + toast + nav
    HomeView.swift         Dog list
    FridgeView.swift       My Fridge — household food DB, grouped by category
    DashboardView.swift    Calorie ring, live activity, today's log
    HouseholdView.swift    Members, invite code
    CaptureFlow.swift      Scan/Photo/Manual capture coordinator
    ConfirmView.swift      Confirm the AI/typed draft
    AssignView.swift       Assign-to-dogs + per-dog allergen check
    ManualEntryView.swift  Type in a food's nutrition
    OnboardingView.swift   12-step first-run flow (SwiftUI port of the DC design)
    OnboardingModel.swift  Onboarding state + mapping to Dog
    Components.swift        Shared UI (chips, rings, buttons, flow layout)
  Capture/
    CameraViews.swift        Camera/photo-library picker (PhotoCaptureView)
    LabelOCR.swift           Vision OCR + no-AI fallback draft
    AppleAI.swift            Apple Foundation Models: label draft + batch meal estimate
    NaturalFoodCatalog.swift ~28 natural foods, USDA-style per-100g + portion grams
    AIDraftService.swift     FoodAI: photos/meals → Product drafts (on-device pipeline)
  Supabase/
    SupabaseConfig.swift   Project URL + publishable key
    SupabaseService.swift  Client, DTOs, auth, queries, realtime (#if canImport(Supabase))
    CloudStore.swift       SupabaseStore adapter: DTO↔model mapping + CloudSync engine
    AppleSignIn.swift       ASAuthorizationController coordinator (nonce + SHA256)
    README-supabase.md      SDK/auth setup steps
supabase/migrations/       0001 schema, 0002 RLS, 0003 RPCs + realtime,
                           0004 member-update policy + 6-char invite codes (SQL)
supabase/functions/
  product-draft/index.ts   Edge function: photo → Claude vision → structured draft
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

### 3.8 SupabaseStore adapter (cloud sync) — added 2026-07-29
- `Supabase/CloudStore.swift`: `CloudMap` (DTO ↔ `Dog`/`LogEntry`/`Member`/
  `Product` mapping) + `CloudSync` engine owned by `AppStore`. Compiles to a
  no-op stub without the SDK; app builds & runs either way.
- **Sync model:** local-first optimistic writes; when signed in, every write
  (create/join household, add dog, log product, rename user) is pushed on a
  serial chain so ordering holds. Row ids are client-generated UUIDs shared by
  local + cloud, so pushes are idempotent upserts and pulls reconcile cleanly.
- **Bootstrap on auth:** cloud household exists → pull (cloud wins; local JSON
  becomes the offline cache). Only local data exists → one-time migration push,
  then re-pull. Signed out → local-only, exactly as before.
- **Realtime:** subscribes to `log_entries`/`dogs`/`members` for the household;
  events trigger a debounced re-pull (powers the shared "fed by" strip).
- **Join is real now** (when signed in): `join_household` RPC resolves the code
  and pulls the household's dogs/log over the local stub; bad code → toast.
- **Invite codes are 6-char** (e.g. `4B29K7`) to match the designed UI — local
  generator + server `gen_invite_code()` (migration 0004) + join input (now
  accepts letters). Migration 0004 was applied to the live project 2026-07-29.
- On cloud pull, `log` holds **today's** household entries (what the dashboard
  shows); older history stays server-side for the future Trends screen.
- Known quirk: the onboarding **Invite step still shows a placeholder code**
  ("4B29K7" hardcoded) because the household is only created at "Start using
  Milo". The real code is in the Household tab.

### 3.9 On-device AI capture + nutrition pipeline — rebuilt 2026-07-29
Product-decision reset (same day): **no barcode, no cloud AI — Apple-only.**
Barcode scanning and the Claude edge-function path were removed from the app
(the `product-draft` edge function is still deployed but dormant/unused; safe
to delete). Architecture: **AI estimates, engine calculates.**
- **Package capture (guided two-shot):** photo 1 = front of bag, photo 2 =
  nutrition label (skippable). Both are OCR'd on-device (Apple Vision), then
  **Apple Foundation Models** (iOS 26, `@Generable` guided generation) turns
  the text into a structured `LabelDraft` — name/brand/category/serving/kcal +
  the full **guaranteed analysis** (crude protein, fat, fiber, moisture %).
  Percent→grams-per-serving conversion happens in Swift, not the model.
- **Natural foods:** brand-less items ("shredded chicken", "1 breast",
  "handful") via a meal composer. `NaturalFoodCatalog` (USDA-style per-100 g
  values + colloquial-portion gram map) resolves common foods
  deterministically; only unknowns go to the foundation model — **one batched
  call per meal, never per item** (deliberate UX + efficiency rule).
- **Meals:** the whole meal is composed first, estimated in one pass, shown as
  an itemized Confirm card (combined allergy check across all ingredients),
  then logged as one LogEntry per food per dog.
- **Nutrition model:** `Product` now carries protein/fat/fiber/moisture grams
  per portion (optional). `CalorieEngine.proteinTargetG/fatTargetG` scale
  AAFCO per-1000-kcal minimums (adult 45/13.8 g, growth 56.3/21.3 g) by the
  dog's calorie target. Dashboard gained a "Nutrition today" card (protein/fat
  bars vs targets; fiber & moisture as info). Manual entry gained the four
  guaranteed-analysis fields. Cloud `products` table gained the columns
  (migration 0005, applied).
- **Fallbacks:** no Apple Intelligence (device/OS) → OCR heuristics + catalog +
  manual fill; unresolvable items surface as "fill in" on Confirm — the app
  never invents numbers. Simulator-verified: Package panel + dashboard
  nutrition card render; AAFCO targets compute correctly (1450 kcal → 65 g
  protein / 20 g fat).

### 3.9b My Fridge + categories + dedupe — same day
- **My Fridge tab** (tab bar is now Home · Fridge · FAB · Trends): the
  household's product database (backed by `favorites` locally / `products` in
  the cloud), grouped by category, each row logs again in two taps (sheet →
  AssignView), long-press → Remove from Fridge (cloud delete too). "Add food"
  opens the capture flow; **Confirm gained a small "Add to Fridge" button** to
  save without logging.
- **Categories:** `FoodCategory` is now kibble / wet / treat / meat / fish /
  vegetable / fruit / dairy / grain / supplement / other, with emoji + labels.
  Legacy values decode via `FoodCategory(legacy:)` (meal→kibble, addIn→other);
  DB check constraint relaxed accordingly (migration 0006, applied). Treat-%
  now counts everything that isn't kibble/wet. Manual entry uses a scrollable
  chip picker; catalog + AFM prompts categorize automatically.
- **No duplicates, ever:** `upsertFridgeItem` merges by name+brand
  (case-insensitive), keeping the existing id and the best-known nutrition;
  `logProduct` canonicalizes through it, so re-capturing or re-logging the
  same food reuses one product row locally and in the cloud.
- **Nutrition rings:** the dashboard card now renders protein/fat as real
  mini-rings (ProgressRing) vs AAFCO targets, fiber/moisture as chips.
- **Package capture:** both photos are required; the CTA stays disabled until
  front + nutrition label are both attached (no "front first" nagging).
- Simulator-verified: Fridge tab (grouped, counts, tab bar), dashboard rings
  (28/65 g protein, 14/20 g fat after a 380 kcal kibble log), live strip.

### 3.9d Capture-accuracy pass (Apple on-device stack) — added 2026-07-31
Four changes to make the capture pipeline more accurate, all Apple-only /
on-device, keeping the hard rule **AI estimates, engine calculates** (the model
never does arithmetic). Everything is availability-gated with graceful fallback.
- **Table-aware label reading** (`LabelOCR.swift`): package capture now uses a
  new `LabelOCR.read(_:)` reader. On **iOS 26** it runs Vision's
  `RecognizeDocumentsRequest` so the guaranteed-analysis grid arrives as clean
  `key | value` rows (`LabelReading.combinedText` prepends the serialized table
  block before the transcript), and it first runs
  `VNDetectDocumentSegmentationRequest` + `CIPerspectiveCorrection` to auto-crop
  and flatten an angled label. Older OS versions fall back to the plain
  `VNRecognizeTextRequest` path (still present, also used by the no-AI draft).
- **Tool-calling for fresh-food estimates** (`AppleAI.swift`): the meal session
  now takes a FoundationModels `Tool` — `NutritionLookupTool` (name
  `lookupNutrition`) — that queries `NaturalFoodCatalog` for USDA-style per-100 g
  values. The model's job is reduced to identifying the food + portion grams and
  reporting `catalogMatch`; when it hit the catalog, **Swift recomputes**
  kcal/protein/fat from per-100 g × grams via the new
  `NaturalFoodCatalog.product(for:grams:portion:)` (see
  `FoodAI.product(from:slot:)`), discarding the model's own numbers. Still **one
  batched model call per meal**, and the deterministic catalog-first path stays
  for exact matches.
- **AI fallback for allergen matching** (`AppleAI.mapAllergens` +
  `AllergenEngine.unmatchedIngredients` / `canonicalAllergens`): the synonym map
  runs first; only ingredients it can't place at all (e.g. "hydrolyzed poultry
  by-product") go to the model in one batched call that maps them to the ten
  canonical allergens. Applied in the package path
  (`FoodAI.withAISuggestedAllergens`) — discovered allergens are appended to the
  product's ingredients as **advisory suggestions** the owner reviews/edits on
  Confirm (safety-conservative: better to surface a flag than miss it).
- **Plausibility guardrails** (`Plausibility` in `AIDraftService.swift`, pure
  rules, no AI): after extraction, `Plausibility.check(_:combined:)` sanity-checks
  the numbers — treat 1–150 kcal/piece, a cup of dry food ~250–550 kcal, dry food
  ~3,000–4,500 kcal/kg, and a guaranteed-analysis mass/energy consistency check
  (nutrient grams can't outweigh the serving mass estimated from calories;
  protein·4 + fat·9 can't exceed the stated calories). Implausible fields are
  flagged on Confirm in an **orange "…double-check" state** on the specific field
  (Calories / Nutrition rows, plus a ⚠︎ marker on implausible meal items) —
  **never silently accepted or auto-corrected**, and the Continue gate is
  unaffected. DEBUG deep-link `MILO_CONFIRM_SAMPLE=implausible` seeds a sample
  that trips the guardrails for screenshot verification.
- **Verified (simulator, iPhone 17 Pro):** Confirm renders the orange guardrail
  state on the implausible sample (both Calories and Nutrition flagged) and shows
  no false positives on the normal sample; Fresh composer + capture entry points
  still render. The Foundation Models / iOS 26 Vision document paths need real
  Apple Intelligence hardware to exercise end-to-end — on the sim they degrade to
  the catalog + plain OCR + manual fill, as designed.

### 3.9c Trustworthy-core UX pass — same day
- **Daily reset:** all day-math (ring, treats %, nutrient rings, Today list,
  live strip) counts TODAY's entries only via `todaysEntries(for:)`; history
  stays in `log` for the future Trends screen. Verified: yesterday's 380 kcal
  entry doesn't move today's ring.
- **Confirm is actually editable:** tapping the product card (or any meal
  item row) opens `ProductEditorSheet` — name/brand/category/kcal/portion/
  guaranteed-analysis/ingredients, with a live allergen-chip preview; saves
  keep the same product id (dedupe holds). Continue + Add-to-Fridge are
  disabled until every item has calories ("fill in" gate).
- **Delete a log entry:** long-press any Today row → Delete (syncs a cloud
  delete; rings correct instantly).
- **Allergy override friction:** logging to a hard-allergic dog now requires
  a destructive confirmation dialog ("X is allergic to Y — Log anyway").
- **Haptics** (`Haptics.swift`): success on log/fridge-save, warning on the
  allergy dialog, light ticks on steppers and category chips.
- Known polish still open: Dynamic Type/VoiceOver, dark mode, fractional
  portions (needs `portionCount` Int→Double + column change), backdating,
  Fridge search, dead Trends tab, custom camera UI.

### 3.10 Git
- Repo initialised; `.gitignore` excludes build output/DerivedData. Commits:
  `Initial commit` → `email auth + Supabase SDK` → `breed catalog + calorie
  engine`.

---

## 4. What's PENDING

**Backend / auth (blocking real cloud sync):**
1. ~~Apply migration 0004~~ — **DONE 2026-07-29** (applied to
   `lxkjhflvxrygtzmjrhqh`, verified: `gen_invite_code()` returns 6-char codes).
2. **Enable the Email provider** in Supabase → Auth → Sign In / Providers, and
   turn **"Confirm email" OFF** for instant dev signups. (Currently email is
   off, so "Continue with email" will error.)
3. **Configure the Apple provider** in Supabase (Service ID + key) for the Apple
   sign-in round-trip to authenticate. Needs a paid Apple Developer account.
4. **End-to-end cloud test** — the adapter (§3.8) is built and the app builds &
   launches with it, but no live signup→onboard→log→realtime round-trip has
   run yet (blocked on 1–2). Test with two simulators for the realtime strip.

**Distribution:**
5. ~~Push to GitHub~~ — done 2026-07-29: `github.com/avj99/Milo` via SSH
   (key `~/.ssh/id_ed25519` on this Mac). Push after each session.
6. **Real signing/provisioning** for device builds + TestFlight (Apple Developer
   team, App IDs, capabilities).

**Product (Phase 2+ from the build guide):**
7. **Finish the on-device capture pipeline** (§3.9 built it). Remaining:
   (a) test on a real Apple Intelligence device (iPhone 15 Pro+, iOS 26) —
   Simulator on this Mac may run Foundation Models if Apple Intelligence is
   enabled in macOS System Settings, otherwise the catalog/OCR fallback runs;
   (b) make Confirm's fields actually editable in place (the ✎ affordance is
   visual-only today — ManualEntryView is the workaround for corrections);
   (c) run AI ingredient output through `AllergenEngine.normalize` at Confirm;
   (d) delete the dormant `product-draft` edge function if the Apple-only
   decision is final.
8. **Crowdsourced product database** — unverified→verified gate, moderation
   queue, report/flag control (Apple UGC guideline 1.2), seed from Open Pet Food
   Facts.
9. **Multi-dog household UX** — add-another-dog UI; the backend join + realtime
   "fed by Mom, 4 min ago" now exist via the adapter (§3.8), but the onboarding
   Invite step still shows a placeholder code, and there's no in-app "add dog"
   after onboarding.
10. **Trends screen** (tab exists, not built — server keeps full log history
    for it), account deletion (App Store req), privacy nutrition labels, "Data
    sources & licenses" screen.
11. **Breed catalog depth** — expand beyond ~65 breeds; consider sex-specific
    ranges; "recalculate as your puppy grows" reminders.

**Housekeeping:**
12. Remove/gate off the DEBUG launch hooks before release. Move the Supabase
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
