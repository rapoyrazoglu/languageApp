import SwiftUI
import PaktlyKit

/// Single-language detail: every pack in the registry that targets a given
/// language, with quality-tier filter chips (All / Official / Community)
/// and a level filter row underneath. Tapping a row pushes PackDetailView.
///
/// Per spec there is NO upload UX here — community packs land in the
/// registry via GitHub-pull (creator publishes a release, backend ingests).
/// This screen is read-only.
struct LanguageDetailView: View {
    @EnvironmentObject private var services: AppServices
    let route: LanguageRoute

    @State private var packs: [Pack] = []
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var tierFilter: TierFilter = .all
    @State private var levelFilter: String?

    enum TierFilter: Hashable, CaseIterable {
        case all, official, community

        var label: LocalizedStringKey {
            switch self {
            case .all:       return "languageDetail.tier.all"
            case .official:  return "languageDetail.tier.official"
            case .community: return "languageDetail.tier.community"
            }
        }
    }

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()
            content
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(DS.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { if packs.isEmpty { await refresh() } }
    }

    private var navigationTitle: String {
        if let code = route.code {
            return LanguageFlag.displayName(for: code)
        }
        return route.level.map { "\($0) packs" } ?? "Discover"
    }

    @ViewBuilder
    private var content: some View {
        if let error = loadError, packs.isEmpty {
            errorView(message: error)
        } else if isLoading && packs.isEmpty {
            ProgressView().tint(DS.accent)
        } else if filteredPacks.isEmpty {
            emptyView
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    filterBar
                    ForEach(filteredPacks) { pack in
                        NavigationLink(value: pack) {
                            DetailPackRow(pack: pack)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 140)
            }
            .scrollContentBackground(.hidden)
            .refreshable { await refresh() }
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Tier chips with App Store-style counts.
            HStack(spacing: 8) {
                ForEach(TierFilter.allCases, id: \.self) { f in
                    let count = countFor(tier: f)
                    Button {
                        tierFilter = f
                    } label: {
                        HStack(spacing: 4) {
                            Text(f.label)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .heavy, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    tierFilter == f
                                        ? Color.white.opacity(0.22)
                                        : DS.divider
                                )
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(tierFilter == f ? .white : DS.textPrimary)
                        .background(tierFilter == f ? DS.textPrimary : DS.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(tierFilter == f ? .clear : DS.divider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }

            // Level chips — only the levels actually present in the catalog.
            if !availableLevels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        levelChip(level: nil, label: "languageDetail.level.all")
                        ForEach(availableLevels, id: \.self) { level in
                            levelChip(level: level, label: LocalizedStringKey(level))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func levelChip(level: String?, label: LocalizedStringKey) -> some View {
        let isActive = levelFilter == level
        Button {
            levelFilter = level
        } label: {
            Group {
                if let level {
                    // Level codes like "A1" / "B2" / "N5" are not catalog
                    // keys — render verbatim so SwiftUI doesn't try to look
                    // them up and waste a fall-back.
                    Text(verbatim: level)
                } else {
                    Text(label)
                }
            }
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? DS.accentInk : DS.textSecondary)
            .background(isActive ? DS.accentMuted : DS.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isActive ? .clear : DS.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Slicing

    private var filteredPacks: [Pack] {
        var result = packs

        switch tierFilter {
        case .all: break
        case .official:
            result = result.filter { QualityTier.derive($0) == .official }
        case .community:
            result = result.filter { QualityTier.derive($0) != .official }
        }

        if let level = levelFilter {
            result = result.filter { $0.level == level }
        }

        return result
    }

    private var availableLevels: [String] {
        let order = ["A1", "A2", "B1", "B2", "C1", "C2"]
        let present = Set(packs.compactMap { $0.level })
        return order.filter { present.contains($0) }
    }

    private func countFor(tier: TierFilter) -> Int {
        let tieredPacks = packs.filter { pack in
            switch tier {
            case .all: return true
            case .official: return QualityTier.derive(pack) == .official
            case .community: return QualityTier.derive(pack) != .official
            }
        }
        if let level = levelFilter {
            return tieredPacks.filter { $0.level == level }.count
        }
        return tieredPacks.count
    }

    // MARK: - Edge

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(DS.textTertiary)
            Text("languageDetail.empty.title")
                .font(.dsTitle2)
                .foregroundStyle(DS.textPrimary)
            Text("languageDetail.empty.body")
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
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
            Button("error.retry") { Task { await refresh() } }
                .buttonStyle(.primaryPill)
                .padding(.horizontal, 60)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Network

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil
        do {
            // We over-fetch and slice client-side. The list endpoint accepts
            // language + level filters server-side; pass them along when
            // present so the wire payload stays small.
            let page = try await services.registry.listPacks(
                language: route.code,
                level: route.level,
                limit: 100
            )
            self.packs = page.packs
        } catch {
            self.loadError = friendly(error)
        }
    }
}

// MARK: - Author avatar

/// Small initials bubble shown next to the author name. Derives both the
/// initials and the background hue from the name string so the same author
/// always renders the same colour.
private struct AuthorAvatar: View {
    let name: String

    private var initials: String {
        let words = name
            .trimmingCharacters(in: .whitespaces)
            .split(separator: " ")
            .prefix(2)
        let parts = words.compactMap { $0.first.map { String($0).uppercased() } }
        let joined = parts.joined()
        return joined.isEmpty ? "?" : String(joined.prefix(2))
    }

    private var hue: DS.PackHue { DS.PackHue.forPack(name) }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [hue.color, hue.ink],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(verbatim: initials)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 18, height: 18)
        .clipShape(Circle())
    }
}

// MARK: - Pack row used here

private struct DetailPackRow: View {
    let pack: Pack
    private var tier: QualityTier { QualityTier.derive(pack) }
    private var hue: DS.PackHue { DS.PackHue.forPack(pack.id) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(
                    colors: [hue.color, hue.ink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text(LanguageFlag.emoji(for: pack.languageCode))
                    .font(.system(size: 24))
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(pack.name)
                        .font(.dsHeadline)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(1)
                    QualityTierBadge(tier: tier, compact: true)
                }
                if let desc = pack.description, !desc.isEmpty {
                    Text(desc)
                        .font(.dsCallout)
                        .foregroundStyle(DS.textSecondary)
                        .lineLimit(2)
                }
                // Per spec: "yapan avatar + ad + beğeni". Avatar is an
                // initials bubble derived from authorName (no creator
                // photos in the registry yet). Like-count slot is reserved
                // for Phase 6 telemetry; nothing to render until that
                // ships, so we leave it out rather than fake it.
                HStack(spacing: 6) {
                    AuthorAvatar(name: pack.authorName)
                    Text(verbatim: pack.authorName)
                        .font(.dsCaption)
                        .foregroundStyle(DS.textSecondary)
                    if let level = pack.level {
                        Text(verbatim: "·").foregroundStyle(DS.textTertiary)
                        DSChip(text: level)
                    }
                    if let v = pack.latestVersion {
                        Text(verbatim: "·").foregroundStyle(DS.textTertiary)
                        Text(verbatim: "v\(v)")
                            .font(.dsCaptionMono)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(DS.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.divider, lineWidth: 1)
        )
    }
}
