import SwiftUI
import PaktlyKit

/// Login + register modal. Auth is optional — pack browse and install work
/// anonymously. Logged-in state only matters for uploading your own packs.
struct AuthSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable {
        case login, register
    }

    @State private var mode: Mode = .login
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var displayName: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DS.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        modeCard
                        formCard
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.dsCallout)
                                .foregroundStyle(DS.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                        }
                        submitButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("auth.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("auth.cancel") { dismiss() }
                        .foregroundStyle(DS.accent)
                }
            }
        }
    }

    // MARK: - Sub-views

    private var modeCard: some View {
        Picker("auth.mode", selection: $mode) {
            Text("auth.mode.login").tag(Mode.login)
            Text("auth.mode.register").tag(Mode.register)
        }
        .pickerStyle(.segmented)
        .padding(4)
        .background(DS.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(label: "auth.email") {
                TextField("you@example.com", text: $email)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    #endif
            }
            divider
            field(label: "auth.password") {
                SecureField("••••••••", text: $password)
            }
            if mode == .register {
                divider
                field(label: "auth.displayName") {
                    TextField("", text: $displayName, prompt: Text("auth.displayName"))
                }
            }
        }
        .dsCard()
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().tint(.white)
                }
                Text(mode == .login ? "auth.button.login" : "auth.button.register")
            }
        }
        .buttonStyle(.primaryPill)
        .disabled(!canSubmit || isSubmitting)
    }

    private var divider: some View {
        Rectangle().fill(DS.divider).frame(height: 1)
    }

    @ViewBuilder
    private func field<Content: View>(label: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.dsCaption)
                .foregroundStyle(DS.textSecondary)
            content()
                .font(.dsBody)
        }
    }

    // MARK: - Logic

    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else { return false }
        guard password.count >= 8 else { return false }
        return true
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch mode {
            case .login:
                try await services.login(email: email, password: password)
            case .register:
                let name = displayName.trimmingCharacters(in: .whitespaces)
                try await services.register(
                    email: email,
                    password: password,
                    displayName: name.isEmpty ? nil : name
                )
            }
            dismiss()
        } catch {
            errorMessage = friendly(error)
        }
    }
}
