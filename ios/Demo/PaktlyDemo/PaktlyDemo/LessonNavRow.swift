import SwiftUI
import PaktlyKit

/// Horizontal row at the bottom of the screen containing the floating tab
/// bar and — when a lesson is on screen — circular ← / → chevrons that
/// drive the lesson's `LessonRunnerState` directly. Outside a lesson, only
/// the tab bar shows. Same layer, same vertical position; the chevrons
/// just appear when relevant.
struct LessonNavRow: View {
    @Binding var selection: AppServices.Tab
    let lessonState: LessonRunnerState?

    var body: some View {
        HStack(spacing: 10) {
            if let state = lessonState {
                LessonNavCircle(direction: .back, state: state)
                    .transition(.scale.combined(with: .opacity))
            }
            FloatingTabBar(selection: $selection)
            if let state = lessonState {
                LessonNavCircle(direction: .next, state: state)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: lessonState != nil)
    }
}

/// Circular 3D chevron. Same press physics as the lesson nodes — the
/// nav action lives on the same visual hierarchy, so it uses the same
/// shelf depth and timing.
struct LessonNavCircle: View {
    enum Direction { case back, next }

    let direction: Direction
    /// `@ObservedObject` not `@StateObject` — the state is owned by
    /// `LessonRunnerScreen`; this view just reads / drives it so SwiftUI
    /// re-renders when `index` (and therefore canGoBack / canAdvance)
    /// change.
    @ObservedObject var state: LessonRunnerState

    var body: some View {
        Button(action: tap) {
            Image(systemName: direction == .back ? "chevron.left" : "chevron.right")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(isEnabled ? DS.accentInk : DS.textTertiary)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.pressable3DCircle(
            face: isEnabled ? DS.surface : DS.surfaceMuted,
            shelf: DS.divider,
            depth: 6
        ))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.55)
    }

    private var isEnabled: Bool {
        switch direction {
        case .back: return state.canGoBack
        case .next: return state.canAdvance
        }
    }

    private func tap() {
        switch direction {
        case .back: state.goBack()
        case .next: state.advance()
        }
    }
}
