import SwiftUI
import PaktlyKit

/// Winding lesson path that fills the screen.
///
/// Per design spec:
/// - node diameter **84pt**, shelf depth **8pt**
/// - vertical pitch (centre-to-centre) **200pt** = 84 + 116 gap
/// - swing pattern **[-78, -26, +26, +78, +26, -26]** (6-cycle, sine-like)
/// - connector **cubic Bezier, 4pt dashed (6/8), divider colour**
/// - current node has a **3pt accent ring** and a **soft 1.6s breathing**
///   animation (scale 1.0 → 1.04, autoreverses, honors `reduceMotion`)
struct LessonPathView: View {
    let lessons: [LessonRef]
    let currentId: String?
    /// Called when the user taps a locked node — caller decides whether to
    /// surface a placement-test sheet or just refuse the tap. Defaults to
    /// no-op so previews still compile.
    var onLockedTap: (LessonRef) -> Void = { _ in }

    private let nodeSize: CGFloat = 84
    private let nodeGap: CGFloat = 116
    /// Big top pad ensures the START callout (which sits 68pt above the
    /// first node and is itself 44pt tall) doesn't get clipped under the
    /// pack header when scrolled to the very top.
    private let topPad: CGFloat = 120
    private var rowPitch: CGFloat { nodeSize + nodeGap }
    private let xCycle: [CGFloat] = [-78, -26, 26, 78, 26, -26]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                connectors(in: geo.size.width)
                nodes(in: geo.size.width)
            }
        }
        .frame(height: CGFloat(max(1, lessons.count)) * rowPitch + topPad - nodeGap)
    }

    // MARK: - Layers

    /// Cubic Bezier between every consecutive pair of node centres. Cubic
    /// (vs quadratic) gives a smoother S-curve when the swing pattern
    /// alternates aggressively.
    private func connectors(in width: CGFloat) -> some View {
        Path { path in
            let centres = (0..<lessons.count).map { position(at: $0, width: width) }
            guard let first = centres.first else { return }
            path.move(to: first)
            for (idx, end) in centres.dropFirst().enumerated() {
                let start = centres[idx]
                // Vertical control points = same x as endpoints, y at the
                // halfway height. Produces a smooth S between staggered
                // nodes; if both nodes share an x (cycle index 1 → 2) the
                // curve degenerates gracefully into a straight vertical.
                let midY = (start.y + end.y) / 2
                let c1 = CGPoint(x: start.x, y: midY)
                let c2 = CGPoint(x: end.x, y: midY)
                path.addCurve(to: end, control1: c1, control2: c2)
            }
        }
        .stroke(
            DS.divider,
            style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [6, 8])
        )
    }

    private func nodes(in width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { idx, ref in
                LessonNode(
                    ref: ref,
                    state: state(for: ref, at: idx),
                    showStartCallout: ref.id == currentId,
                    onLockedTap: { onLockedTap(ref) }
                )
                .frame(width: nodeSize, height: nodeSize)
                .position(position(at: idx, width: width))
            }
        }
    }

    // MARK: - Geometry

    private func position(at idx: Int, width: CGFloat) -> CGPoint {
        let x = width / 2 + xCycle[idx % xCycle.count]
        let y = topPad + CGFloat(idx) * rowPitch + nodeSize / 2
        return CGPoint(x: x, y: y)
    }

    /// Per spec: only three states on a path — completed, current, locked.
    /// Future lessons are locked, not "upcoming" — the user has to either
    /// finish what's in front of them or pass a placement test. The
    /// `.upcoming` case is retained on the enum for any future "preview"
    /// affordance but isn't currently produced.
    private func state(for ref: LessonRef, at idx: Int) -> LessonNodeState {
        guard let currentId,
              let currentIdx = lessons.firstIndex(where: { $0.id == currentId })
        else {
            return idx == 0 ? .current : .locked
        }
        if idx < currentIdx { return .completed }
        if idx == currentIdx { return .current }
        return .locked
    }
}

// MARK: - Node states

enum LessonNodeState {
    case completed
    case current
    case upcoming
    case locked
}

// MARK: - Single node

struct LessonNode: View {
    let ref: LessonRef
    let state: LessonNodeState
    let showStartCallout: Bool
    let onLockedTap: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Driven by `withAnimation(.repeatForever)` in onAppear — the older
    /// `.animation(_:value:)` modifier with a one-shot bool flip is
    /// unreliable on iOS 16; the explicit `withAnimation` form actually
    /// schedules the loop.
    @State private var breathScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .top) {
            interactiveNode
                .scaleEffect(breathScale)
                .onAppear { startBreathingIfCurrent() }
                .onChange(of: state) { _ in startBreathingIfCurrent() }

            if showStartCallout {
                StartCallout()
                    .offset(y: -68)  // 84/2 + 36/2 + 12pt clearance, per spec
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
    }

    /// Per spec section 4: only the current node breathes (1.6s ease-in-out,
    /// 1.0 → 1.04, autoreverses forever). Completed / locked stay still.
    /// Honours reduceMotion.
    private func startBreathingIfCurrent() {
        guard state == .current, !reduceMotion else {
            breathScale = 1.0
            return
        }
        breathScale = 1.0
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            breathScale = 1.04
        }
    }

    /// Locked nodes route to the placement-test sheet via the closure;
    /// completed and current nodes use NavigationLink so the navigation
    /// stack handles them. Splitting like this keeps the buttonStyle press
    /// physics on both paths without a custom PrimitiveButtonStyle.
    @ViewBuilder
    private var interactiveNode: some View {
        if state == .locked {
            Button(action: onLockedTap) {
                glyph
            }
            .buttonStyle(.pressable3DCircle(
                face: face, shelf: shelf, depth: 8
            ))
        } else {
            NavigationLink(value: ref) {
                glyph
            }
            .buttonStyle(.pressable3DCircle(
                face: face,
                shelf: shelf,
                depth: 8,
                ringWidth: state == .current ? 3 : 0,
                ringColor: DS.accent
            ))
        }
    }

    /// Per spec section 4: current uses an OUTLINE star drawn in ink
    /// colour, not a green filled star. Completed shows a heavy
    /// checkmark; upcoming a small dot; locked a small lock.
    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(.white)
        case .current:
            Image(systemName: "star")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(DS.textPrimary)
        case .upcoming:
            Circle()
                .fill(DS.textTertiary.opacity(0.55))
                .frame(width: 12, height: 12)
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(DS.textTertiary.opacity(0.55))
        }
    }

    /// Per spec section 4:
    /// - Completed: accent face + accentInk shelf
    /// - **Current: white face + INK shelf** (ring is 3pt accent, drawn
    ///   by the button style)
    /// - Upcoming: white face + soft gray shelf
    /// - Locked: muted face + soft gray shelf
    private var face: Color {
        switch state {
        case .completed: return DS.accent
        case .current:   return DS.surface
        case .upcoming:  return DS.surface
        case .locked:    return DS.surfaceMuted
        }
    }

    private var shelf: Color {
        switch state {
        case .completed: return DS.accentInk
        case .current:   return DS.textPrimary  // ink — spec section 4
        case .upcoming:  return DS.divider
        case .locked:    return DS.divider
        }
    }
}

// MARK: - "START" callout

/// Per spec: 86×36pt rounded pill with an 8pt triangle pointer pointing
/// down at the current node. Background = textPrimary (dark ink), label =
/// background (paper). Soft breathing animation (scale 1.0 → 1.04, 1.6s
/// ease-in-out, autoreverses) replaces the previous bouncing translate —
/// less attention-grabbing, more premium. Honors reduceMotion.
struct StartCallout: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            Text("START")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(DS.background)
                .frame(width: 86, height: 36)
                .background(DS.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Triangle()
                .fill(DS.textPrimary)
                .frame(width: 14, height: 8)
        }
        .scaleEffect(scale)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                scale = 1.04
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.closeSubpath()
        }
    }
}
