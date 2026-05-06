import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Color shelf helper

extension Color {
    /// Slightly darker shade for the 3D button shelf. Walks HSB and trims
    /// brightness; falls back to the original on macOS / non-UIKit surfaces.
    func dsDarken(by amount: CGFloat = 0.18) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getHue(&h, saturation: &s, brightness: &b, alpha: &a) {
            return Color(uiColor: UIColor(
                hue: h,
                saturation: min(1, s + amount * 0.4),
                brightness: max(0, b - amount),
                alpha: a
            ))
        }
        #endif
        return self
    }
}

// MARK: - Rectangle 3D button

/// Duolingo-style "physical" button. Per spec: shelf depth 8pt, press
/// translates 8pt down so the face lands flush on the shelf, animation is
/// a tight spring (response 0.18, damping 0.65 — matches the
/// cubic-bezier(0.2, 0.8, 0.2, 1) reference curve).
struct Pressable3DButtonStyle: ButtonStyle {
    let face: Color
    let shelf: Color?
    let cornerRadius: CGFloat
    let depth: CGFloat
    let textColor: Color

    init(
        face: Color,
        shelf: Color? = nil,
        cornerRadius: CGFloat = 16,
        depth: CGFloat = 8,
        textColor: Color = .white
    ) {
        self.face = face
        self.shelf = shelf
        self.cornerRadius = cornerRadius
        self.depth = depth
        self.textColor = textColor
    }

    func makeBody(configuration: Configuration) -> some View {
        let computedShelf = shelf ?? face.dsDarken()
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(computedShelf)
                .offset(y: depth)

            configuration.label
                .font(.system(.body, design: .rounded, weight: .heavy))
                .foregroundStyle(textColor)
                .padding(.vertical, 14)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(face)
                )
                .offset(y: configuration.isPressed ? depth : 0)
        }
        .compositingGroup()
        .padding(.bottom, depth)
        .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Circle 3D button

struct Pressable3DCircleStyle: ButtonStyle {
    let face: Color
    let shelf: Color?
    let depth: CGFloat
    let ringWidth: CGFloat
    let ringColor: Color

    init(
        face: Color,
        shelf: Color? = nil,
        depth: CGFloat = 8,
        ringWidth: CGFloat = 0,
        ringColor: Color = .clear
    ) {
        self.face = face
        self.shelf = shelf
        self.depth = depth
        self.ringWidth = ringWidth
        self.ringColor = ringColor
    }

    func makeBody(configuration: Configuration) -> some View {
        let computedShelf = shelf ?? face.dsDarken()
        ZStack(alignment: .top) {
            Circle()
                .fill(computedShelf)
                .offset(y: depth)

            ZStack {
                Circle().fill(face)
                if ringWidth > 0 {
                    Circle()
                        .stroke(ringColor, lineWidth: ringWidth)
                        .padding(ringWidth / 2)
                }
                configuration.label
            }
            .offset(y: configuration.isPressed ? depth : 0)
        }
        .compositingGroup()
        .animation(.spring(response: 0.18, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Convenience adapters

extension ButtonStyle where Self == Pressable3DButtonStyle {
    static func pressable3D(
        face: Color,
        shelf: Color? = nil,
        cornerRadius: CGFloat = 16,
        depth: CGFloat = 8,
        textColor: Color = .white
    ) -> Pressable3DButtonStyle {
        Pressable3DButtonStyle(
            face: face, shelf: shelf,
            cornerRadius: cornerRadius, depth: depth, textColor: textColor
        )
    }
}

extension ButtonStyle where Self == Pressable3DCircleStyle {
    static func pressable3DCircle(
        face: Color,
        shelf: Color? = nil,
        depth: CGFloat = 8,
        ringWidth: CGFloat = 0,
        ringColor: Color = .clear
    ) -> Pressable3DCircleStyle {
        Pressable3DCircleStyle(
            face: face, shelf: shelf,
            depth: depth, ringWidth: ringWidth, ringColor: ringColor
        )
    }
}

// MARK: - Convenience pill variants

/// `.primaryPill` — featured CTA. 3D shelf, accent face. Reach for this on
/// install / submit / continue buttons.
extension ButtonStyle where Self == Pressable3DButtonStyle {
    static var primaryPill: Pressable3DButtonStyle {
        Pressable3DButtonStyle(face: DS.accent, shelf: DS.accentInk, cornerRadius: 18, depth: 8, textColor: .white)
    }

    /// Destructive CTA. Same physics, red face. Used for "Remove" actions.
    static var destructivePill: Pressable3DButtonStyle {
        Pressable3DButtonStyle(face: DS.danger, cornerRadius: 18, depth: 8, textColor: .white)
    }
}

/// `.secondaryPill` — flat capsule for non-primary actions. No shelf — the
/// 3D treatment is reserved for the screen's featured CTA so it stays
/// special. Used for tertiary buttons like "Reset", "Skip", etc.
struct SecondaryPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .heavy))
            .foregroundStyle(DS.textPrimary)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .background(DS.surfaceMuted.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(Capsule())
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SecondaryPillButtonStyle {
    static var secondaryPill: SecondaryPillButtonStyle { .init() }
}
