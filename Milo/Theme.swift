import SwiftUI

/// Design tokens lifted directly from the Milo mockup (`pawtrition-mockup_1.html`).
/// Keeping them in one place means every screen reads from the same palette,
/// type scale, and radii — the app should feel like one system, not many.
enum Theme {

    // MARK: Palette
    static let bg          = Color(hex: 0xEFF2ED)
    static let card        = Color(hex: 0xFFFFFF)
    static let ink         = Color(hex: 0x1B2B25)
    static let brand       = Color(hex: 0x2A5D4E)
    static let brandDeep   = Color(hex: 0x1F473B)
    static let accent      = Color(hex: 0xF2A93B)
    static let accentDeep  = Color(hex: 0xD98A1F)
    static let accentSoft  = Color(hex: 0xFBEAC9)
    static let alert       = Color(hex: 0xDB5A4B)
    static let alertSoft   = Color(hex: 0xFBE3E0)
    static let muted       = Color(hex: 0x6E7B74)
    static let line        = Color(hex: 0xE4E8E2)
    static let track       = Color(hex: 0xEDF0EC)

    // Chip / member accents
    static let okChipBg    = Color(hex: 0xE4F0E9)
    static let momA        = Color(hex: 0xE9885E)
    static let momB        = Color(hex: 0xDB5A4B)
    static let dadA        = Color(hex: 0x5FA3C9)
    static let dadB        = Color(hex: 0x3C7BA6)
    static let kidA        = Color(hex: 0x8FBF6E)
    static let kidB        = Color(hex: 0x5E9A3F)

    // MARK: Gradients
    static let ringGradient = LinearGradient(
        colors: [Color(hex: 0xF6C86B), Color(hex: 0xD98A1F)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let overGradient = LinearGradient(
        colors: [Color(hex: 0xE9885E), alert],
        startPoint: .leading, endPoint: .trailing)

    static let brandGradient = LinearGradient(
        colors: [brand, brandDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let barGradient = LinearGradient(
        colors: [accent, accentDeep],
        startPoint: .leading, endPoint: .trailing)

    static let pageBackground = LinearGradient(
        colors: [Color(hex: 0xE7EBE5), Color(hex: 0xE7EBE5)],
        startPoint: .top, endPoint: .bottom)

    // MARK: Radii
    static let rCard: CGFloat = 26
    static let rRow: CGFloat  = 20
    static let rPill: CGFloat = 16
}

// MARK: - Nunito-flavoured type scale
// The mockup uses Nunito (a rounded sans). We ship with the system rounded
// design so the app looks right without bundling a font file.
extension Font {
    static func milo(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Standard card surface used across the app.
    func miloCard(radius: CGFloat = Theme.rRow, padding: CGFloat = 15) -> some View {
        self
            .padding(padding)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1))
    }
}

// MARK: - Color(hex:)
extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: alpha)
    }
}
