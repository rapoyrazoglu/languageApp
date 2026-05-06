import SwiftUI
import PaktlyKit

/// Settings: account state, registry URL (for self-host), and an About
/// section with build metadata. Token persistence uses UserDefaults for now;
/// Phase 5 hardening moves it to the Keychain.
struct SettingsView: View {
    @EnvironmentObject private var services: AppServices

    @State private var showAuth: Bool = false
    @State private var registryURLDraft: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                DS.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        accountCard
                        registryCard
                        aboutCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("nav.settings.title")
            .toolbarBackground(DS.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showAuth) {
                AuthSheet()
            }
            .onAppear {
                registryURLDraft = services.registryURL.absoluteString
            }
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader(title: "settings.account")

            if let user = services.currentUser {
                row(label: "settings.signedInAs", value: user.email)
                if let name = user.displayName, !name.isEmpty {
                    divider
                    row(label: "settings.displayName", value: name)
                }
                divider
                Button(role: .destructive) {
                    Task { await services.logout() }
                } label: {
                    Label("settings.logout", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.destructivePill)
            } else {
                Text("settings.notSignedIn")
                    .font(.dsCallout)
                    .foregroundStyle(DS.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    showAuth = true
                } label: {
                    Label("settings.login", systemImage: "person.crop.circle")
                }
                .buttonStyle(.primaryPill)
            }
        }
        .dsCard()
    }

    // MARK: - Registry

    private var registryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader(title: "settings.registry", subtitle: "settings.registry.help")

            VStack(alignment: .leading, spacing: 6) {
                Text("settings.registryURL")
                    .font(.dsCaption)
                    .foregroundStyle(DS.textSecondary)
                TextField("", text: $registryURLDraft, prompt: Text("https://api.paktly.dev"))
                    .padding(12)
                    .background(DS.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            }

            HStack(spacing: 10) {
                Button("settings.useDefault") {
                    registryURLDraft = "https://api.paktly.dev"
                    applyURL()
                }
                .buttonStyle(.secondaryPill)

                Button("settings.apply") { applyURL() }
                    .buttonStyle(.primaryPill)
                    .disabled(registryURLDraft == services.registryURL.absoluteString)
            }
        }
        .dsCard()
    }

    // MARK: - About

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DSSectionHeader(title: "settings.about")

            row(label: "settings.version", value: appVersion)
            divider
            row(label: "settings.author", value: "Paktly")
            divider

            Link(destination: URL(string: "https://github.com/rapoyrazoglu/languageApp")!) {
                HStack {
                    Label("settings.sourceCode", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(.dsCallout)
                        .foregroundStyle(DS.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.callout)
                        .foregroundStyle(DS.textTertiary)
                }
            }
            divider

            Link(destination: URL(string: "https://paktly.dev")!) {
                HStack {
                    Label("settings.website", systemImage: "globe")
                        .font(.dsCallout)
                        .foregroundStyle(DS.accent)
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .font(.callout)
                        .foregroundStyle(DS.textTertiary)
                }
            }
        }
        .dsCard()
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle().fill(DS.divider).frame(height: 1)
    }

    private func row(label: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(DS.textSecondary)
            Spacer()
            Text(value)
                .font(.dsCallout)
                .foregroundStyle(DS.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }

    private func applyURL() {
        let trimmed = registryURLDraft.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased())
        else { return }
        services.registryURL = url
    }

    private var appVersion: String {
        let main = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(main) (\(build))"
    }
}
