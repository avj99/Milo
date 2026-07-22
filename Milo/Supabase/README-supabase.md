# Milo × Supabase — finishing the wiring

The database (schema, RLS, RPCs, realtime) is already applied to project
`lxkjhflvxrygtzmjrhqh`. The Swift side is scaffolded but **dormant** until you
add the SDK — everything in `SupabaseService.swift` is behind
`#if canImport(Supabase)`, so the app builds fine right now.

## 1. Add the Supabase Swift package (in Xcode)

1. Open `Milo.xcodeproj`.
2. **File → Add Package Dependencies…**
3. Enter: `https://github.com/supabase/supabase-swift`
4. Dependency Rule: **Up to Next Major**, from `2.0.0`.
5. Add the **`Supabase`** product to the **Milo** target.

Once it resolves, `canImport(Supabase)` becomes true and `SupabaseService`
compiles. (There's no pbxproj change to make by hand — Xcode writes the package
reference for you.)

## 2. Enable Sign in with Apple

1. Select the **Milo** target → **Signing & Capabilities**.
2. Set your **Team** (needs a paid Apple Developer account).
3. **+ Capability → Sign in with Apple**.
4. In the **Supabase dashboard → Authentication → Providers → Apple**, enable it
   and fill in your Services ID / key (Supabase's guide walks through the Apple
   Developer portal steps).

Then wire the button: use `ASAuthorizationAppleIDButton` / `SignInWithAppleButton`,
generate a random nonce, hash it (SHA256) for the Apple request, and pass the
returned `identityToken` + the **raw** nonce to:

```swift
try await SupabaseService.shared.signInWithApple(idToken: token, nonce: rawNonce)
```

## 3. Swap the in-memory store for Supabase

`AppStore` currently holds seeded sample data. To go live, replace its reads
with the service calls (all already written):

| AppStore today | Supabase call |
|---|---|
| seeded `dogs` | `try await SupabaseService.shared.dogs()` (+ `allergens(dogID:)`) |
| seeded `members` / `household` | `myHousehold()` / `members()` |
| `logProduct(...)` | `insertLogEntries([...])` |
| onboarding "create household" | `createHousehold(name:memberName:)` |
| onboarding "join with code" | `joinHousehold(code:memberName:)` |
| live "fed by Mom" strip | `householdChannel(householdID:)` realtime stream |

Map the DTOs (`DogDTO`, `LogEntryDTO`, …) to the existing app models
(`Dog`, `LogEntry`, …) in one adapter layer so the views don't change.

Say the word and I'll write that adapter + a `SupabaseStore` that conforms to
the same shape as `AppStore`, so the UI switches over with a one-line change in
`MiloApp`.

## Notes
- The publishable key in `SupabaseConfig.swift` is public and safe to commit.
- The three SQL migrations live in `supabase/migrations/` for source control /
  re-applying to another project.
