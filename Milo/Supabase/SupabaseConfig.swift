import Foundation

/// Connection details for the Milo Supabase project (`lxkjhflvxrygtzmjrhqh`,
/// in the TrustPacketAI org — the schema/RLS/RPCs are already applied there).
///
/// The publishable key is **safe to ship** inside the app — row-level security
/// on every table is what actually protects data, scoping reads and writes to
/// the caller's household. To rotate it: dashboard → Project Settings → API keys.
///
/// To move Milo to a different Supabase project later, change these two values
/// and run `supabase/migrations/*.sql` against the new project.
enum SupabaseConfig {
    static let url = URL(string: "https://lxkjhflvxrygtzmjrhqh.supabase.co")!
    static let publishableKey = "sb_publishable_81eIsGrRoCAF8aFtO0SJVQ_W0wzWxvj"
}
