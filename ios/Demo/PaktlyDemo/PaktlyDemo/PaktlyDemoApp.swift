import SwiftUI

@main
struct PaktlyDemoApp: App {
    @StateObject private var services = AppServices()

    init() {
        // Pin the demo to Turkish until the per-user language preference
        // ships in Settings. This sidesteps the bilingual feel the user
        // gets when the simulator is in English but only TR/EN are filled
        // in the string catalog. Production app will follow the user's
        // own choice (and fall back to device locale when none is set).
        UserDefaults.standard.set(["tr"], forKey: "AppleLanguages")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.locale, Locale(identifier: "tr"))
                .environmentObject(services)
                .task { await services.bootstrap() }
        }
    }
}
