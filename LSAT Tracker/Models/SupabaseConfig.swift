import Foundation

/// The Supabase project that carries the Account's Clock State and Sessions
/// (ADR 0003). The publishable key is meant to ship inside client apps; row
/// level security on the server is what protects the data.
///
/// The same project backs Russian Tracker, under the same `auth.users`, but
/// this app only ever touches its own `lsat_clock_state` / `lsat_sessions`
/// tables — the two apps never see each other's rows.
nonisolated enum SupabaseConfig {
    static let url = URL(string: "https://wnwquybkpmyaufwkjmqw.supabase.co")!
    static let publishableKey = "sb_publishable_xGdg4ZEo7AfVT14qr4wReQ_RfK0XKOE"
}
