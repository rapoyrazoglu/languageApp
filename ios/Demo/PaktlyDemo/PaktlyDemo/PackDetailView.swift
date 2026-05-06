import SwiftUI
import PaktlyKit

/// Pack detail page. Hero header, manifest fields in card sections, version
/// list, and primary install / remove CTA. Once installed, an "Open" link
/// drops the user into the lesson list.
struct PackDetailView: View {
    @EnvironmentObject private var services: AppServices
    let pack: Pack

    @State private var versions: [PackVersion] = []
    @State private var installed: InstalledPack?
    @State private var isLoadingDetail: Bool = false
    @State private var detailError: String?
    @State private var isInstalling: Bool = false
    @State private var installError: String?

    var body: some View {
        ZStack {
            DS.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    actionCard
                    metadataCard
                    versionsCard
                    if let detailError {
                        Text(detailError)
                            .font(.dsCallout)
                            .foregroundStyle(DS.danger)
                            .padding(.horizontal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadDetail() }
    }

    // MARK: - Sub-views

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                DSLanguageBadge(code: pack.languageCode)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pack.name)
                        .font(.dsLargeTitle)
                        .foregroundStyle(DS.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let level = pack.level { DSChip(text: level) }
                        Text(pack.languageName)
                            .font(.dsCallout)
                            .foregroundStyle(DS.textSecondary)
                    }
                }
                Spacer(minLength: 4)
            }
            if let desc = pack.description, !desc.isEmpty {
                Text(desc)
                    .font(.dsBody)
                    .foregroundStyle(DS.textSecondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var actionCard: some View {
        VStack(spacing: 10) {
            if let installed {
                Button {
                    services.selectPack(packId: installed.packId)
                    services.selectedTab = .home
                } label: {
                    Label("packDetail.open", systemImage: "play.fill")
                }
                .buttonStyle(.primaryPill)

                Button(role: .destructive) {
                    Task { await remove(installedPack: installed) }
                } label: {
                    Label("packDetail.remove", systemImage: "trash")
                }
                .buttonStyle(.destructivePill)
            } else {
                Button {
                    Task { await install() }
                } label: {
                    HStack(spacing: 6) {
                        if isInstalling {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text("packDetail.install")
                    }
                }
                .buttonStyle(.primaryPill)
                .disabled(isInstalling || pack.latestVersion == nil)

                if let err = installError {
                    Text(err)
                        .font(.dsCallout)
                        .foregroundStyle(DS.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .dsCard(padding: 14)
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: "packDetail.id", value: pack.id, monospaced: true)
            divider
            row(label: "packDetail.author", value: pack.authorName)
            divider
            row(label: "packDetail.license", value: pack.license)
            if let v = pack.latestVersion {
                divider
                row(label: "packDetail.latestVersion", value: v, monospaced: true)
            }
            if !pack.tags.isEmpty {
                divider
                row(label: "packDetail.tags", value: pack.tags.joined(separator: ", "))
            }
        }
        .dsCard()
    }

    @ViewBuilder
    private var versionsCard: some View {
        if !versions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("packDetail.versions")
                    .font(.dsHeadline)
                    .foregroundStyle(DS.textPrimary)
                ForEach(versions, id: \.version) { v in
                    HStack {
                        Text("v\(v.version)")
                            .font(.system(.callout, design: .monospaced, weight: .medium))
                            .foregroundStyle(DS.textPrimary)
                        Spacer()
                        DSChip(text: v.source.rawValue.uppercased(), tint: DS.textSecondary)
                        Text(formatBytes(v.sizeBytes))
                            .font(.dsCaptionMono)
                            .foregroundStyle(DS.textTertiary)
                    }
                }
            }
            .dsCard()
        } else if isLoadingDetail {
            HStack {
                Spacer()
                ProgressView().tint(DS.accent)
                Spacer()
            }
            .padding()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.divider)
            .frame(height: 1)
    }

    private func row(label: LocalizedStringKey, value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .dsCallout)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    // MARK: - Network

    private func loadDetail() async {
        installed = try? await services.store.installed(packId: pack.id, version: pack.latestVersion ?? "")
        await fetchVersions()
    }

    private func fetchVersions() async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            let detail = try await services.registry.getPack(id: pack.id)
            self.versions = detail.versions
        } catch {
            self.detailError = friendly(error)
        }
    }

    private func install() async {
        guard let version = pack.latestVersion else {
            installError = String(localized: "error.noLatestVersion")
            return
        }
        isInstalling = true
        installError = nil
        defer { isInstalling = false }
        do {
            let pack = try await services.store.download(
                packId: pack.id,
                version: version,
                from: services.registry
            )
            self.installed = pack
        } catch {
            self.installError = friendly(error)
        }
    }

    private func remove(installedPack: InstalledPack) async {
        do {
            try await services.store.remove(packId: installedPack.packId, version: installedPack.version)
            self.installed = nil
        } catch {
            self.installError = friendly(error)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
