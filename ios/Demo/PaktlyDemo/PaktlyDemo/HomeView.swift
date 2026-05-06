import SwiftUI
import PaktlyKit

/// Home — the lesson-first surface.
///
/// Layout, top to bottom:
///   ╭ language-pill (top-left, ~40pt) ┄ optional streak chip (top-right) ╮
///   ┊                                                                    ┊
///   ┊ pack header — caption + title + meta (~60pt total)                 ┊
///   ┊                                                                    ┊
///   ┊                  winding lesson path (the focus)                   ┊
///   ┊                                                                    ┊
///   ╰ floating tab bar (rendered by RootView) ─────────────────────────-─╯
///
/// No gradient hero card, no duplicated metadata — the path itself carries
/// the screen, exactly the design spec's intent.
struct HomeView: View {
    @EnvironmentObject private var services: AppServices

    @State private var activePack: InstalledPack?
    @State private var showPicker: Bool = false
    @State private var isLoading: Bool = false
    @State private var placementTarget: LessonRef?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                DS.background.ignoresSafeArea()
                content
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await refresh() }
            .onChange(of: services.currentPackId) { _ in
                Task { await refresh() }
            }
            .sheet(isPresented: $showPicker) {
                PackPickerSheet(active: activePack) { selectedPackId in
                    services.selectPack(packId: selectedPackId)
                    showPicker = false
                }
            }
            .sheet(item: $placementTarget) { target in
                if let pack = activePack {
                    PlacementTestSheet(
                        pack: pack,
                        target: target,
                        lessonsToCover: lessonsBetweenCurrentAnd(target: target, in: pack)
                    ) {
                        services.setCurrentLesson(packId: pack.packId, lessonId: target.id)
                    }
                }
            }
            .navigationDestination(for: LessonRef.self) { ref in
                if let pack = activePack {
                    LessonRunnerScreen(pack: pack, lessonRef: ref)
                        .onAppear {
                            services.setCurrentLesson(packId: pack.packId, lessonId: ref.id)
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let pack = activePack {
            withPack(pack)
        } else if isLoading {
            ProgressView().tint(DS.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyHome { services.selectedTab = .discover }
        }
    }

    // MARK: - Pack on screen

    private func withPack(_ pack: InstalledPack) -> some View {
        let resumeId = services.currentLessonByPack[pack.packId]
            ?? pack.manifest.lessons.first?.id

        return VStack(spacing: 0) {
            topBar(for: pack)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            packHeader(for: pack)
                .padding(.horizontal, 24)
                .padding(.top, 16)

            ScrollView {
                LessonPathView(
                    lessons: pack.manifest.lessons,
                    currentId: resumeId,
                    onLockedTap: { ref in placementTarget = ref }
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 140)  // breathing room above the floating tab bar
            }
            .scrollContentBackground(.hidden)
        }
    }

    /// Lessons strictly between the user's current lesson and the target
    /// they tapped — these are what the placement test covers.
    private func lessonsBetweenCurrentAnd(target: LessonRef, in pack: InstalledPack) -> [LessonRef] {
        let lessons = pack.manifest.lessons
        guard let targetIdx = lessons.firstIndex(where: { $0.id == target.id }) else {
            return []
        }
        let currentIdx: Int
        if let currentId = services.currentLessonByPack[pack.packId],
           let idx = lessons.firstIndex(where: { $0.id == currentId }) {
            currentIdx = idx
        } else {
            currentIdx = 0
        }
        guard targetIdx > currentIdx else { return [] }
        return Array(lessons[currentIdx..<targetIdx])
    }

    private func topBar(for pack: InstalledPack) -> some View {
        HStack {
            DSLanguagePill(
                nativeName: pack.manifest.language.nativeName ?? pack.manifest.language.name,
                languageCode: pack.manifest.language.code,
                level: pack.manifest.level?.rawValue,
                onTap: { showPicker = true }
            )
            Spacer()
            // Reserved slot for the streak chip — wired in Phase 6 when we
            // ship the SRS data layer.
        }
    }

    private func packHeader(for pack: InstalledPack) -> some View {
        VStack(alignment: .center, spacing: 4) {
            Text("home.pack.caption")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(DS.textTertiary)
                .textCase(.uppercase)

            Text(pack.manifest.name)
                .font(.dsTitle2)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(pack.manifest.language.name)
                Text("·").foregroundStyle(DS.textTertiary)
                Text("\(pack.manifest.lessons.count) lessons")
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        activePack = await services.currentInstalledPack()

        if activePack == nil, services.currentPackId != nil {
            services.currentPackId = nil
        }
        if activePack == nil, services.currentPackId == nil,
           let first = (try? await services.store.installedPacks())?.first {
            services.selectPack(packId: first.packId)
            activePack = first
        }
    }
}

// MARK: - Empty home

private struct EmptyHome: View {
    let onDiscover: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(DS.accent.opacity(0.7))
            VStack(spacing: 6) {
                Text("home.empty.title")
                    .font(.dsTitle)
                    .foregroundStyle(DS.textPrimary)
                Text("home.empty.body")
                    .font(.dsCallout)
                    .foregroundStyle(DS.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                onDiscover()
            } label: {
                Label("home.empty.cta", systemImage: "sparkles")
            }
            .buttonStyle(.pressable3D(face: DS.accent, depth: 8))
            .padding(.horizontal, 56)
        }
        .padding(.bottom, 120)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
