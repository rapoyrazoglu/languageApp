import SwiftUI

/// Custom floating tab bar — replaces the native `UITabBar`. Per spec
/// anti-example: native chrome makes the app feel like "another iOS app".
/// This pill floats 28pt off the bottom safe area, has a translucent
/// material backing, and the active tab swells with an `accentMuted` pill
/// behind its label so the user sees their position at a glance.
struct FloatingTabBar: View {
    @Binding var selection: AppServices.Tab

    var body: some View {
        HStack(spacing: 4) {
            tab(.home,     icon: "house.fill",                label: "tab.home")
            tab(.discover, icon: "sparkles.rectangle.stack",  label: "tab.browse")
            tab(.settings, icon: "gearshape.fill",            label: "tab.settings")
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(DS.divider, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
    }

    @ViewBuilder
    private func tab(_ which: AppServices.Tab, icon: String, label: LocalizedStringKey) -> some View {
        let isActive = selection == which
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selection = which
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                if isActive {
                    Text(label)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isActive ? DS.accentInk : DS.textSecondary)
            .padding(.horizontal, isActive ? 14 : 12)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(isActive ? DS.accentMuted : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
