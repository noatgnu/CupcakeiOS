import SwiftUI

/// The reference web app's login form also has a "Remember Me" checkbox (extends the JWT
/// refresh token's lifetime — `login.html:107-120`). Deliberately not reproduced here: this
/// app's `AuthManager.signIn` exchanges the JWT for a `DeviceToken` within seconds and discards
/// the JWT immediately after (see its doc comment) — `DeviceToken` has no expiry by default
/// regardless of how long the now-discarded JWT would have lived, so the toggle would affect
/// nothing in this app's actual auth flow. Adding it anyway would be misleading UI, not fidelity.
struct LoginView: View {
    @Environment(AppSession.self) private var appSession

    @State private var serverURLString = "https://cupcake.proteo.info/api/v1/"
    @State private var username = ""
    @State private var password = ""
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Server") {
                TextField("Server URL", text: $serverURLString)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("serverURLField")
            }
            Section("Account") {
                TextField("Username", text: $username)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("usernameField")
                SecureField("Password", text: $password)
                    .accessibilityIdentifier("passwordField")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    signIn()
                } label: {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(isSigningIn || serverURLString.isEmpty || username.isEmpty || password.isEmpty)
                .accessibilityIdentifier("signInButton")
            }
            Section {
                Button {
                    signInWithORCID()
                } label: {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign in with ORCID")
                    }
                }
                .disabled(isSigningIn || serverURLString.isEmpty)
                .accessibilityIdentifier("signInWithOrcidButton")
            }
            Section {
                Button("Continue Offline") {
                    appSession.continueOffline()
                }
                .disabled(isSigningIn)
                .accessibilityIdentifier("continueOfflineButton")
            } footer: {
                Text("Use Cupcake as a personal, local-only lab notebook with no server — everything you create stays on this device until you sign in later.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cupcake")
        .frame(minWidth: 320, minHeight: 320)
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await appSession.signIn(serverURLString: serverURLString, username: username, password: password)
            } catch {
                errorMessage = "Sign in failed: \(error.localizedDescription)"
            }
        }
    }

    private func signInWithORCID() {
        errorMessage = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await appSession.signInWithORCID(serverURLString: serverURLString)
            } catch {
                errorMessage = "ORCID sign in failed: \(error.localizedDescription)"
            }
        }
    }
}
