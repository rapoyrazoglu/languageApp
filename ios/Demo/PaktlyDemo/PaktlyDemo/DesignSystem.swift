import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color tokens

/// Paper-white + Duo-green. The palette deliberately puts only one dominant
/// accent on the screen (`#58CC02`) — yellow is reserved for streak, red
/// for hearts. Background stays bright white in light mode (paper feel),
/// switches to a near-black with a faint teal cast in dark mode (#131F24)
/// so OLED doesn't halo around the accent.
///
/// Tokens map 1:1 to the design spec at design/Paktly Spec - Home.html.
enum DS {
    // Surface
    static let background   = Color(light: 0xFAFAF7, dark: 0x131F24)
    static let surface      = Color(light: 0xFFFFFF, dark: 0x1F2D33)
    static let surfaceMuted = Color(light: 0xF1F1ED, dark: 0x2A383F)
    static let divider      = Color(light: 0xE8E8E5, dark: 0x37464F)

    // Text
    static let textPrimary   = Color(light: 0x1A1A1A, dark: 0xF7F7F4)
    static let textSecondary = Color(light: 0x6E6E6E, dark: 0xAEB7BB)
    static let textTertiary  = Color(light: 0xA8A8A8, dark: 0x7A858B)

    // Brand — Duo green, identical hex in both modes; surrounding tokens
    // do the heavy lifting for contrast.
    static let accent      = Color(light: 0x58CC02, dark: 0x58CC02)
    static let accentInk   = Color(light: 0x3A8A00, dark: 0x93D851)
    static let accentMuted = Color(light: 0xD7FFB8, dark: 0x1F4A0A)

    // Semantic — tightly scoped:
    //   warning → streak only
    //   danger  → hearts / lost-life only
    static let success = Color(light: 0x58CC02, dark: 0x58CC02)
    static let warning = Color(light: 0xFFC800, dark: 0xFFC800)
    static let danger  = Color(light: 0xFF4B4B, dark: 0xFF6B6B)

    /// Pack-card visual variety for the Discover grid. Per spec
    /// (`design/Discover/Paktly Discover.html` line 102):
    ///   "grid card'ları için renk kodlu (kırmızı / mavi / sarı / turuncu)
    ///    — bu kart background'ları sadece visual variety, hiçbiri marka
    ///    rengi değil."
    /// Strictly four colours. Featured cards do NOT come from this enum —
    /// they always use the brand accent (`#58CC02`) per the same line.
    /// Cycle by stable hash of pack id so the same pack always renders
    /// the same hue.
    enum PackHue: Int, CaseIterable {
        case red, blue, yellow, orange

        static func forPack(_ id: String) -> PackHue {
            let sum = id.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
            let cases = PackHue.allCases
            return cases[abs(sum) % cases.count]
        }

        var color: Color {
            switch self {
            case .red:    return Color(light: 0xE5535B, dark: 0xE5535B)
            case .blue:   return Color(light: 0x4D9CE5, dark: 0x4D9CE5)
            case .yellow: return Color(light: 0xF0B83A, dark: 0xF0B83A)
            case .orange: return Color(light: 0xF08C3A, dark: 0xF08C3A)
            }
        }

        /// Slightly darker companion for the 3D shelf or "ink" text on top.
        var ink: Color {
            switch self {
            case .red:    return Color(light: 0xA12C32, dark: 0xF59298)
            case .blue:   return Color(light: 0x2C6AAE, dark: 0xA0C8EE)
            case .yellow: return Color(light: 0x9C7515, dark: 0xF6D88B)
            case .orange: return Color(light: 0xAB5A14, dark: 0xF6BC8B)
            }
        }
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        #if canImport(UIKit)
        self = Color(uiColor: UIColor { trait in
            UIColor(rgbHex: trait.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        self = Color(red: Double((light >> 16) & 0xff) / 255,
                     green: Double((light >> 8) & 0xff) / 255,
                     blue: Double(light & 0xff) / 255)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(rgbHex: UInt32) {
        self.init(
            red: Double((rgbHex >> 16) & 0xff) / 255,
            green: Double((rgbHex >> 8) & 0xff) / 255,
            blue: Double(rgbHex & 0xff) / 255,
            alpha: 1
        )
    }
}
#endif

// MARK: - Card style

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(DS.divider, lineWidth: 1)
            )
    }
}

extension View {
    func dsCard(padding: CGFloat = 16, cornerRadius: CGFloat = 20) -> some View {
        modifier(CardStyle(padding: padding, cornerRadius: cornerRadius))
    }
}

// MARK: - Typography (SF Pro Rounded everywhere)

extension Font {
    static let dsLargeTitle  = Font.system(size: 34, weight: .bold,     design: .rounded)
    static let dsTitle       = Font.system(size: 28, weight: .bold,     design: .rounded)
    static let dsTitle2      = Font.system(size: 22, weight: .bold,     design: .rounded)
    static let dsHeadline    = Font.system(size: 17, weight: .semibold, design: .rounded)
    static let dsBody        = Font.system(size: 16, weight: .medium,   design: .rounded)
    static let dsCallout     = Font.system(size: 15, weight: .regular,  design: .rounded)
    static let dsCaption     = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let dsCaptionMono = Font.system(size: 12, weight: .medium,   design: .monospaced)
}

// MARK: - Reusable bits

struct DSSectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(DS.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.dsCallout)
                    .foregroundStyle(DS.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DSChip: View {
    let text: String
    var tint: Color = DS.accent
    var background: Color? = nil

    var body: some View {
        Text(text)
            .font(.dsCaption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(background ?? tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }
}

/// 44pt rounded square showing an ISO 639 code in the brand accent. Used in
/// list rows and pack cards as a quick visual anchor for the target language.
struct DSLanguageBadge: View {
    let code: String

    var body: some View {
        Text(String(code.prefix(2)).uppercased())
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(DS.accentInk)
            .frame(width: 44, height: 44)
            .background(DS.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Localized "language pill" used at the top of HomeView. Per spec we render
/// the language's *native script* (日本語, 한국어, …) instead of the country
/// emoji flag — flags are politically loaded and emoji rendering varies by
/// platform. Native script is neutral and respectful of the language itself.
struct DSLanguagePill: View {
    let nativeName: String
    let languageCode: String
    let level: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text(displayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                if let level {
                    Text(level)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.accentInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(DS.accentMuted)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(DS.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DS.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(DS.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var displayName: String {
        if !nativeName.isEmpty { return nativeName }
        return languageCode.uppercased()
    }
}

// MARK: - Global background

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            DS.background.ignoresSafeArea()
            content
        }
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackground()) }
}
