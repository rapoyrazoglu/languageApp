import SwiftUI
import PaktlyKit

/// Bottom sheet that lets the user switch between installed packs, grouped
/// by the speaker audience (`uiLanguage`). Each group is an open list of
/// installed packs plus a "Discover more" CTA that opens DiscoverView with
/// the group's `uiLanguage` filter pre-applied (and target languages already
/// installed in that group excluded — the user hasn't earned a recommendation
/// for a target they're already studying).
struct PackPickerSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    let active: InstalledPack?
    let onSelect: (String) -> Void

    @State private var allInstalled: [InstalledPack] = []
    @State private var expanded: Set<String> = []
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DS.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if grouped.isEmpty {
                            EmptyPicker {
                                path.append(DiscoverFilter(uiLanguage: nil, excludeTargets: []))
                            }
                            .padding(.top, 32)
                        } else {
                            ForEach(orderedGroups, id: \.self) { uiLang in
                                groupCard(uiLang: uiLang, packs: grouped[uiLang] ?? [])
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("packPicker.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("auth.cancel") { dismiss() }
                        .foregroundStyle(DS.accent)
                }
            }
            .navigationDestination(for: DiscoverFilter.self) { filter in
                DiscoverView(filter: filter)
            }
            .task { await reload() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Group card

    @ViewBuilder
    private func groupCard(uiLang: String, packs: [InstalledPack]) -> some View {
        let isOpen = expanded.contains(uiLang)
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expanded.remove(uiLang) } else { expanded.insert(uiLang) }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LanguageFlag.speakerLabel(for: uiLang))
                            .font(.dsHeadline)
                            .foregroundStyle(DS.textPrimary)
                        Text(packCountLabel(packs.count))
                            .font(.dsCaption)
                            .foregroundStyle(DS.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(DS.textTertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(DS.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(spacing: 8) {
                    ForEach(packs, id: \.self) { pack in
                        Button {
                            onSelect(pack.packId)
                        } label: {
                            installedRow(pack: pack)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        let installedTargets = Set(packs.map { $0.manifest.language.code.lowercased() })
                        path.append(DiscoverFilter(uiLanguage: uiLang, excludeTargets: installedTargets))
                    } label: {
                        Label {
                            Text(String(format: NSLocalizedString("packPicker.discoverIn", comment: ""), LanguageFlag.displayName(for: uiLang)))
                                .font(.dsCallout.weight(.semibold))
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                        .foregroundStyle(DS.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DS.accentMuted)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 10)
                .padding(.horizontal, 8)
                .transition(.opacity)
            }
        }
        .padding(.bottom, 4)
    }

    private func installedRow(pack: InstalledPack) -> some View {
        let isActive = pack.packId == active?.packId
        return HStack(spacing: 12) {
            Text(LanguageFlag.emoji(for: pack.manifest.language.code))
                .font(.system(size: 30))
            VStack(alignment: .leading, spacing: 2) {
                Text(pack.manifest.name)
                    .font(.dsHeadline)
                    .foregroundStyle(DS.textPrimary)
                HStack(spacing: 6) {
                    if let level = pack.manifest.level {
                        DSChip(text: level.rawValue)
                    }
                    Text("v\(pack.manifest.version)")
                        .font(.dsCaptionMono)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DS.accent)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(isActive ? DS.accentMuted : DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Data

    private var grouped: [String: [InstalledPack]] {
        Dictionary(grouping: allInstalled) { pack in
            (pack.manifest.uiLanguage ?? "und").lowercased()
        }
    }

    private var orderedGroups: [String] {
        grouped.keys.sorted { lhs, rhs in
            // Active pack's group surfaces first; otherwise alphabetical by
            // display name so the order stays predictable.
            let lhsHasActive = grouped[lhs]?.contains(where: { $0.packId == active?.packId }) ?? false
            let rhsHasActive = grouped[rhs]?.contains(where: { $0.packId == active?.packId }) ?? false
            if lhsHasActive != rhsHasActive { return lhsHasActive }
            return LanguageFlag.displayName(for: lhs) < LanguageFlag.displayName(for: rhs)
        }
    }

    private func packCountLabel(_ count: Int) -> String {
        count == 1 ? "1 pack" : "\(count) packs"
    }

    private func reload() async {
        let installed = (try? await services.store.installedPacks()) ?? []
        self.allInstalled = installed

        // Auto-expand the active pack's group, plus any singleton group, so
        // the picker is useful without an extra tap.
        if let active = active {
            expanded.insert((active.manifest.uiLanguage ?? "und").lowercased())
        }
        if grouped.count == 1, let only = grouped.keys.first {
            expanded.insert(only)
        }
    }
}

private struct EmptyPicker: View {
    let onDiscover: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(DS.accent.opacity(0.5))
            Text("packPicker.empty.title")
                .font(.dsTitle2)
                .foregroundStyle(DS.textPrimary)
            Text("packPicker.empty.body")
                .font(.dsCallout)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                onDiscover()
            } label: {
                Label("packPicker.empty.cta", systemImage: "sparkles")
            }
            .buttonStyle(.primaryPill)
            .padding(.horizontal, 48)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - DiscoverFilter route value

/// Carries pre-applied filters into DiscoverView when navigating from a
/// per-group "Discover more" CTA. Hashable so it works as a NavigationStack
/// route value.
struct DiscoverFilter: Hashable, Identifiable {
    var id: String { "\(uiLanguage ?? "any")|\(excludeTargets.sorted().joined(separator: ","))" }
    let uiLanguage: String?
    let excludeTargets: Set<String>
}
