import SwiftUI
import PaktlyKit

/// Top-level container. Hosts the custom `FloatingTabBar` plus, when a
/// lesson is in progress, two circular chevrons flanking it that drive
/// `LessonRunnerState`. All three live on the same horizontal row at the
/// bottom of the screen — back / [Home][Browse][Settings] / next.
struct RootView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        ZStack(alignment: .bottom) {
            currentTab
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            LessonNavRow(
                selection: $services.selectedTab,
                lessonState: services.activeLessonState
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(.keyboard)
    }

    @ViewBuilder
    private var currentTab: some View {
        switch services.selectedTab {
        case .home:
            HomeView()
        case .discover:
            NavigationStack { DiscoverView() }
        case .settings:
            SettingsView()
        }
    }
}
