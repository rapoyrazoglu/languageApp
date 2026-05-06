import SwiftUI
import PaktlyKit

/// Pack discovery — App Store-curation aesthetic, Apple Books calm.
///
/// Top to bottom:
///   1. Sticky search + filter chips header (188pt, blur background)
///   2. Featured card (full-width hero, weekly curation)
///   3. "For X speakers" — 2-column grid, 4-6 packs
///   4. "Popular this week" — vertical list, compact rows
///   5. "By level" — 3×2 grid of CEFR levels with pack counts
///
/// Tapping a language card (in the For-X grid) or a level cell pushes
/// `LanguageDetailView` filtered to that language / level.
struct DiscoverView: View {
    @EnvironmentObject private var services: AppServices

    /// Optional pre-applied filter (used when reached from the pack-picker
    /// sheet's per-group "Discover for X speakers" CTA).
    var filter: DiscoverFilter? = nil

    @State private var packs: [Pack] = []
    @State private var query: String = ""
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var filterChip: DiscoverFilterChip = .all

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()
            content
                .navigationDestination(for: Pack.self) { pack in
                    PackDetailView(pack: pack)
                }
                .navigationDestination(for: LanguageRoute.self) { route in
                    LanguageDetailView(route: route)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { if packs.isEmpty { await refresh() } }
    }

    @ViewBuilder
    private var content: some View {
        if filter != nil {
            // Filtered mode (from pack picker) — keep the simpler list view.
            filteredFlatList
        } else {
            mainFeed
        }
    }

    // MARK: - Main feed

    private var mainFeed: some View {
        ScrollView {
            feedSections
                .padding(.top, 16)
                .padding(.bottom, 140)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
        // safeAreaInset is the correct iOS 16+ way to do a sticky top bar.
        // It reserves space at the top — the scroll content stops at the
        // inset's bottom edge instead of bleeding behind it. With a solid
        // DS.background on the header, the status bar area stays clean
        // and the featured card never peeks through above the title.
        .safeAreaInset(edge: .top, spacing: 0) {
            StickyHeader(
                query: $query,
                filter: $filterChip,
                onSubmit: { Task { await refresh() } }
            )
        }
    }

    @ViewBuilder
    private var feedSections: some View {
        if let error = loadError, packs.isEmpty {
            ErrorState(message: error) { Task { await refresh() } }
                .frame(minHeight: 320)
        } else if packs.isEmpty && isLoading {
            ProgressView().tint(DS.accent)
                .frame(maxWidth: .infinity, minHeight: 320)
        } else if !filteredPacks.isEmpty {
            VStack(spacing: 28) {
                if let featured = featuredPack { FeaturedCard(pack: featured) }
                ForXSpeakersGrid(packs: forXSpeakersPacks)
                PopularList(packs: popularPacks)
                ByLevelGrid(packs: filteredPacks)
            }
            .padding(.horizontal, 16)
        } else {
            EmptyState()
                .frame(minHeight: 320)
        }
    }

    // MARK: - Filtered (legacy from pack-picker route)

    private var filteredFlatList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredPacks) { pack in
                    NavigationLink(value: pack) {
                        PackRowView(pack: pack)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 140)
        }
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }

    // MARK: - Slicing

    private var filteredPacks: [Pack] {
        guard let filter else { return matchingQuery(packs) }
        return matchingQuery(packs.filter { pack in
            if let ui = filter.uiLanguage,
               (pack.uiLanguage ?? "").lowercased() != ui.lowercased() {
                return false
            }
            if filter.excludeTargets.contains(pack.languageCode.lowercased()) {
                return false
            }
            return true
        })
    }

    private func matchingQuery(_ source: [Pack]) -> [Pack] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        var pool = source

        // Active filter chip narrows the pool first; the search query is a
        // free-text pass on top.
        switch filterChip {
        case .all:
            break
        case .recent:
            pool = pool.sorted { (a, b) in
                (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
            }
        case .top:
            // Without telemetry, top-rated falls back to "official tier
            // first" — a defensible proxy until Phase 6 ships ratings.
            pool = pool.sorted { a, b in
                let ta = QualityTier.derive(a)
                let tb = QualityTier.derive(b)
                return rank(ta) < rank(tb)
            }
        case .free:
            // Every Paktly pack is free-as-in-CC — chip is here for spec
            // parity; future paid tiers would gate this.
            break
        }

        guard !trimmed.isEmpty else { return pool }
        return pool.filter {
            $0.name.lowercased().contains(trimmed)
                || $0.languageName.lowercased().contains(trimmed)
                || $0.tags.contains(where: { $0.lowercased().contains(trimmed) })
        }
    }

    private func rank(_ tier: QualityTier) -> Int {
        switch tier {
        case .official: return 0
        case .reviewed: return 1
        case .beta:     return 2
        }
    }

    private var featuredPack: Pack? {
        // Pick the largest official pack (most authoritative) — falls back
        // to the first pack if no officials exist.
        filteredPacks.first(where: { QualityTier.derive($0) == .official })
            ?? filteredPacks.first
    }

    private var forXSpeakersPacks: [Pack] {
        let userLang = (Locale.current.language.languageCode?.identifier ?? "tr").lowercased()
        return filteredPacks.filter {
            ($0.uiLanguage ?? "").lowercased() == userLang
        }
    }

    private var popularPacks: [Pack] {
        // Without backend stats, "popular" is an opinionated middle slice —
        // not the featured pack, not the bottom of the list. Real
        // popularity ships with Phase 6 SRS telemetry.
        let pool = filteredPacks.filter { $0.id != featuredPack?.id }
        return Array(pool.prefix(6))
    }

    // MARK: - Network

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            let page = try await services.registry.listPacks(limit: 100)
            self.packs = page.packs
        } catch {
            self.loadError = friendly(error)
        }
    }
}

// MARK: - Sticky header

/// Per spec (`design/Discover/Paktly Discover.html` line 96):
///   "Sticky header (188pt): blur background, 'Discover' title + search bar
///    + horizontal filter pills."
///
/// Layout: title (40pt rounded) on top, search pill, then a horizontal
/// scrollable row of filter chips. Total height ≈ 188pt at default text
/// size. Backed by `.regularMaterial` so the background blurs as the page
/// scrolls underneath.
private struct StickyHeader: View {
    @Binding var query: String
    @Binding var filter: DiscoverFilterChip
    let onSubmit: () -> Void

    var body: some View {
        // Spec target: 188pt total. Title (~38pt) + 14 + search (~44pt) +
        // 14 + filter row (~36pt) + 16 top + 16 bottom = ~178pt; close
        // enough to read as the spec'd height while staying responsive
        // when the system font scales.
        VStack(spacing: 14) {
            HStack {
                Text("nav.browse.title")
                    .font(.dsLargeTitle)
                    .foregroundStyle(DS.textPrimary)
                Spacer()
            }

            // Search pill
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(DS.textSecondary)
                TextField(text: $query, prompt: Text("browse.searchPrompt")) {
                    Text("browse.searchPrompt")
                }
                .submitLabel(.search)
                .onSubmit(onSubmit)
                #if os(iOS)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                #endif
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.surface)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DS.divider, lineWidth: 1))

            // Horizontal filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DiscoverFilterChip.allCases, id: \.self) { chip in
                        FilterPill(chip: chip, active: chip == filter) {
                            filter = chip
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
        // Solid background — `safeAreaInset` already prevents scroll
        // content from rendering behind us, so a translucent material
        // would just expose the status bar / chrome behind. Keep it
        // crisp; a hairline divider at the bottom marks the boundary.
        .background(DS.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.divider)
                .frame(height: 0.5)
        }
    }
}

/// Filter chips in the sticky header — the spec calls these "horizontal
/// filter pills". The active chip is filled with the ink colour; idle chips
/// stay transparent with a hairline border.
enum DiscoverFilterChip: Hashable, CaseIterable {
    case all, recent, top, free

    var label: LocalizedStringKey {
        switch self {
        case .all:    return "discover.filter.all"
        case .recent: return "discover.filter.recent"
        case .top:    return "discover.filter.top"
        case .free:   return "discover.filter.free"
        }
    }
}

private struct FilterPill: View {
    let chip: DiscoverFilterChip
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(chip.label)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(active ? DS.background : DS.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(active ? DS.textPrimary : DS.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(active ? .clear : DS.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Featured card

/// Per spec line 102: "Featured kart hue'ları: #58CC02 (accent)".
/// Featured ALWAYS green — never random. The grid tiles use PackHue for
/// visual variety; the hero stays brand-coloured so it reads as the one
/// curated highlight of the week.
private struct FeaturedCard: View {
    let pack: Pack

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.white)
                Text("discover.featured.tag")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.22))
            .clipShape(Capsule())

            Spacer(minLength: 0)

            Text(pack.name)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            if let desc = pack.description, !desc.isEmpty {
                Text(desc)
                    .font(.dsCallout)
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Text(pack.languageName)
                    .font(.dsCaption)
                    .foregroundStyle(.white.opacity(0.85))
                if let level = pack.level {
                    DSChip(text: level, tint: .white, background: .white.opacity(0.22))
                }
                Spacer()
                NavigationLink(value: pack) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        Text("discover.preview")
                    }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.accentInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.white)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(20)
        // Spec target: 168pt full-width hero. Pin to that height so the
        // card doesn't grow when a creator ships a long description —
        // long descs get truncated by the 2-line lineLimit instead.
        .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168, alignment: .leading)
        .background(
            LinearGradient(
                colors: [DS.accent, DS.accentInk],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: DS.accentInk.opacity(0.25), radius: 16, x: 0, y: 6)
    }
}

// MARK: - For X speakers grid

private struct ForXSpeakersGrid: View {
    let packs: [Pack]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleText(
                LanguageFlag.speakerLabel(for: Locale.current.language.languageCode?.identifier ?? "tr")
            )
            if packs.isEmpty {
                emptyHint
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(packs.prefix(6)) { pack in
                        NavigationLink(value: pack) {
                            PackTileCard(pack: pack)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        Text("discover.forSpeakers.empty")
            .font(.dsCallout)
            .foregroundStyle(DS.textSecondary)
            .padding(.vertical, 8)
    }
}

/// Per spec (line 98): tile carries `flag emoji + native script + en name +
/// level chip + lessons`. Dense info, two visual rows: media tile on top
/// with the level chip overlaid; metadata block below.
private struct PackTileCard: View {
    let pack: Pack
    private var hue: DS.PackHue { DS.PackHue.forPack(pack.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                LanguageGlyphTile(languageCode: pack.languageCode, hue: hue)
                if let level = pack.level {
                    Text(verbatim: level)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.85))
                        .foregroundStyle(hue.ink)
                        .clipShape(Capsule())
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                // Native script (大きい / 한국어 / 日本語) — the user reads this first.
                Text(verbatim: nativeScript)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                // English / locale name underneath, smaller.
                Text(verbatim: LanguageFlag.displayName(for: pack.languageCode))
                    .font(.dsCaption)
                    .foregroundStyle(DS.textSecondary)
                Text(verbatim: pack.name)
                    .font(.dsCallout)
                    .foregroundStyle(DS.textPrimary.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.divider, lineWidth: 1)
        )
    }

    /// Pull the native script from the manifest's pack catalogue row when
    /// available. Falls back to the language's display name (e.g. for
    /// Latin-script languages where the "native script" is just the name).
    private var nativeScript: String {
        let nativeMap: [String: String] = [
            "ja": "日本語", "ko": "한국어", "zh": "中文", "zh-hans": "简体中文",
            "ar": "العربية", "he": "עברית", "hi": "हिन्दी", "ru": "Русский",
            "el": "Ελληνικά", "tr": "Türkçe", "fa": "فارسی", "th": "ไทย",
        ]
        if let script = nativeMap[pack.languageCode.lowercased()] { return script }
        return pack.languageName
    }
}

private struct LanguageGlyphTile: View {
    let languageCode: String
    let hue: DS.PackHue

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [hue.color, hue.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(LanguageFlag.emoji(for: languageCode))
                .font(.system(size: 44))
        }
        .frame(height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Popular this week — list

private struct PopularList: View {
    let packs: [Pack]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleKey("discover.popular.title")
            if packs.isEmpty {
                Text("discover.popular.empty")
                    .font(.dsCallout)
                    .foregroundStyle(DS.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(packs) { pack in
                        NavigationLink(value: pack) {
                            PopularRow(pack: pack)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct PopularRow: View {
    let pack: Pack
    private var tier: QualityTier { QualityTier.derive(pack) }
    private var hue: DS.PackHue { DS.PackHue.forPack(pack.id) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                hue.color
                Text(LanguageFlag.emoji(for: pack.languageCode))
                    .font(.system(size: 22))
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.name)
                    .font(.dsHeadline)
                    .foregroundStyle(DS.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(pack.languageName)
                        .font(.dsCaption)
                        .foregroundStyle(DS.textSecondary)
                    QualityTierBadge(tier: tier, compact: true)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DS.textTertiary)
        }
        .padding(10)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.divider, lineWidth: 1)
        )
    }
}

// MARK: - By level grid

private struct ByLevelGrid: View {
    let packs: [Pack]
    private let order = ["A1", "A2", "B1", "B2", "C1", "C2"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitleKey("discover.byLevel.title")

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
            ], spacing: 10) {
                ForEach(order, id: \.self) { level in
                    let count = packs.filter { $0.level == level }.count
                    NavigationLink(value: LanguageRoute(code: nil, level: level)) {
                        LevelCell(level: level, count: count)
                    }
                    .buttonStyle(.plain)
                    .opacity(count > 0 ? 1 : 0.5)
                    .disabled(count == 0)
                }
            }
        }
    }
}

private struct LevelCell: View {
    let level: String
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: level)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(DS.accentInk)
            Text(
                String.localizedStringWithFormat(
                    NSLocalizedString("packsCount", comment: "Number of packs in a level cell"),
                    count
                )
            )
            .font(.dsCaption)
            .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(DS.accentMuted)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Section title helpers

/// Localised section title — pass a catalog key.
private func sectionTitleKey(_ key: LocalizedStringKey) -> some View {
    Text(key)
        .font(.system(size: 20, weight: .heavy, design: .rounded))
        .foregroundStyle(DS.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

/// Section title for a runtime-built string (e.g. "Türkçe konuşanlar için").
/// Wrapping in `Text(verbatim:)` is explicit so SwiftUI doesn't try to look
/// the result up as a localization key.
private func sectionTitleText(_ literal: String) -> some View {
    Text(verbatim: literal)
        .font(.system(size: 20, weight: .heavy, design: .rounded))
        .foregroundStyle(DS.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Empty + error states (shared)

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(DS.accent.opacity(0.6))
            Text("browse.empty.title")
                .font(.dsTitle2)
                .foregroundStyle(DS.textPrimary)
            Text("browse.empty.body")
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DS.warning)
            Text("error.loadingFailed")
                .font(.dsTitle2)
                .foregroundStyle(DS.textPrimary)
            Text(message)
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("error.retry", action: retry)
                .buttonStyle(.primaryPill)
                .padding(.horizontal, 60)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error mapping

func friendly(_ error: Error) -> String {
    if let registryErr = error as? RegistryError {
        switch registryErr {
        case .invalidURL:
            return String(localized: "error.invalidURL")
        case .transport:
            return String(localized: "error.network")
        case .decoding:
            return String(localized: "error.decoding")
        case .http(_, let code, let message, _, _):
            return "\(code.rawValue): \(message)"
        case .unexpectedResponse(let status, _):
            return String(localized: "error.unexpectedStatus") + " (\(status))"
        }
    }
    return error.localizedDescription
}

// MARK: - Route values

/// Push value for navigating into a language- or level-filtered list.
struct LanguageRoute: Hashable, Identifiable {
    /// ISO 639 language code (target language), or nil when filtering by
    /// level only.
    let code: String?
    /// CEFR level filter, or nil when filtering by language only.
    let level: String?

    var id: String { "\(code ?? "any")|\(level ?? "any")" }
}
