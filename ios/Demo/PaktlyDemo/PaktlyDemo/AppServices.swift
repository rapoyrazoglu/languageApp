import Foundation
import Combine
import PaktlyKit

/// App-level service container. Owns the singletons every screen reaches for —
/// the registry client, the on-device pack store, the audio player, and the
/// session-scoped auth state. Created once in `PaktlyDemoApp` and pushed into
/// the SwiftUI environment so any view can pull what it needs.
///
/// State that callers mutate (`registryURL`, `currentUser`) is `@Published` so
/// SwiftUI redraws when settings change. The actor-bound `RegistryClient` is
/// rebuilt whenever the URL changes — that's the cheapest way to swap base
/// URLs at runtime without leaking partially-constructed clients.
@MainActor
final class AppServices: ObservableObject {
    @Published private(set) var registry: RegistryClient
    let store: PackStore
    let audioPlayer: PaktlyAudioPlayer

    @Published var registryURL: URL {
        didSet {
            UserDefaults.standard.set(registryURL.absoluteString, forKey: Self.registryURLKey)
            registry = RegistryClient(baseURL: registryURL, token: token)
        }
    }

    @Published var currentUser: User?

    /// Bound to the root TabView so any screen can programmatically jump
    /// (e.g. the empty-home button switches to Discover; PackDetailView's
    /// "Open" jumps back to Home after marking a pack active).
    @Published var selectedTab: Tab = .home

    enum Tab: Hashable { case home, discover, settings }

    /// The lesson currently being studied (nil when no lesson is on screen).
    /// RootView watches this so it can flank the floating tab bar with the
    /// lesson's back / next buttons; LessonRunnerScreen sets it on appear
    /// and clears it on disappear.
    @Published var activeLessonState: LessonRunnerState?

    /// The pack the user is currently studying. Persisted across launches so
    /// the app can re-open them right where they left off.
    @Published var currentPackId: String? {
        didSet {
            if let currentPackId {
                UserDefaults.standard.set(currentPackId, forKey: Self.currentPackIdKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.currentPackIdKey)
            }
        }
    }

    /// Resume position within `currentPackId`. Persisted as a `<packId>:<lessonId>`
    /// dict so switching packs doesn't lose the per-pack progress.
    @Published var currentLessonByPack: [String: String] {
        didSet {
            UserDefaults.standard.set(currentLessonByPack, forKey: Self.currentLessonByPackKey)
        }
    }

    private(set) var token: String? {
        didSet {
            if let token {
                UserDefaults.standard.set(token, forKey: Self.tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            }
        }
    }

    private static let registryURLKey = "paktly.registryURL"
    private static let tokenKey = "paktly.token"
    private static let currentPackIdKey = "paktly.currentPackId"
    private static let currentLessonByPackKey = "paktly.currentLessonByPack"
    private static let defaultRegistryURL = URL(string: "https://api.paktly.dev")!

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.registryURLKey).flatMap(URL.init(string:))
        let url = stored ?? Self.defaultRegistryURL
        self.registryURL = url
        self.token = UserDefaults.standard.string(forKey: Self.tokenKey)
        self.registry = RegistryClient(baseURL: url, token: self.token)
        self.store = .default
        self.audioPlayer = PaktlyAudioPlayer()
        self.currentPackId = UserDefaults.standard.string(forKey: Self.currentPackIdKey)
        self.currentLessonByPack = (UserDefaults.standard.dictionary(forKey: Self.currentLessonByPackKey) as? [String: String]) ?? [:]
    }

    // MARK: - Selection

    /// Pin a pack as the user's current focus. Used by the pack picker; the
    /// home screen reads this to decide which pack's lessons to show.
    func selectPack(packId: String) {
        self.currentPackId = packId
    }

    func setCurrentLesson(packId: String, lessonId: String) {
        var copy = self.currentLessonByPack
        copy[packId] = lessonId
        self.currentLessonByPack = copy
    }

    /// Resolve the current `InstalledPack`. Returns `nil` if none is selected
    /// or the selected pack is no longer installed (user uninstalled it
    /// elsewhere).
    func currentInstalledPack() async -> InstalledPack? {
        guard let id = currentPackId else { return nil }
        guard let all = try? await store.installedPacks() else { return nil }
        return all.first { $0.packId == id }
    }

    /// Run one-time tasks at app launch — restore the user record if a token
    /// was stashed across a relaunch, etc. Failures are silent: bad / expired
    /// tokens just leave us logged out, which the UI handles cleanly.
    func bootstrap() async {
        guard token != nil else { return }
        do {
            let me = try await registry.me()
            self.currentUser = me
        } catch {
            // Token expired or registry unreachable — drop the session.
            self.currentUser = nil
            self.token = nil
            await registry.setToken(nil)
        }
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws {
        let response = try await registry.login(email: email, password: password)
        self.token = response.token
        self.currentUser = response.user
    }

    func register(email: String, password: String, displayName: String?) async throws {
        let response = try await registry.register(email: email, password: password, displayName: displayName)
        self.token = response.token
        self.currentUser = response.user
    }

    func logout() async {
        self.currentUser = nil
        self.token = nil
        await registry.setToken(nil)
    }
}
