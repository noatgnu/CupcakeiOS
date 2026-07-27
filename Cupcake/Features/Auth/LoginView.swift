import CupcakeModels
import CupcakeNetworking
import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var appSession

    @State private var serverURLString = "https://cupcake.proteo.info/api/v1/"
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var instancePendingRemoval: KnownInstance?

    private var sortedKnownInstances: [KnownInstance] {
        appSession.knownInstances.sorted {
            ($0.lastSignedInAt ?? .distantPast) > ($1.lastSignedInAt ?? .distantPast)
        }
    }

    var body: some View {
        Form {
            if !sortedKnownInstances.isEmpty {
                Section("Known Instances") {
                    ForEach(sortedKnownInstances) { instance in
                        Button {
                            appSession.switchToInstance(instance)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.label)
                                HStack(spacing: 4) {
                                    if let lastUsername = instance.lastUsername {
                                        Text(lastUsername)
                                    }
                                    Text(instance.baseURLString)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("knownInstanceRow_\(instance.label)")
                        .contextMenu {
                            Button("Forget This Instance", role: .destructive) {
                                instancePendingRemoval = instance
                            }
                        }
                        .swipeActions {
                            Button("Forget", role: .destructive) {
                                instancePendingRemoval = instance
                            }
                        }
                    }
                }
            }
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
                HStack {
                    Group {
                        if isPasswordVisible {
                            TextField("Password", text: $password)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .autocorrectionDisabled()
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .accessibilityIdentifier("passwordField")
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("togglePasswordVisibilityButton")
                    .help(isPasswordVisible ? "Hide Password" : "Show Password")
                }
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
                    appSession.checkForOntologyPreloadPrompt()
                }
                .disabled(isSigningIn)
                .accessibilityIdentifier("continueOfflineButton")
            } footer: {
                Text("Use Cupcake as a personal, local-only lab notebook with no server. Everything you create stays on this device until you sign in later.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cupcake")
        .frame(minWidth: 320, minHeight: 320)
        .alert(
            "Forget \(instancePendingRemoval?.label ?? "this instance")?",
            isPresented: Binding(
                get: { instancePendingRemoval != nil },
                set: { if !$0 { instancePendingRemoval = nil } }
            ),
            presenting: instancePendingRemoval
        ) { instance in
            Button("Cancel", role: .cancel) {}
            Button("Forget", role: .destructive) {
                appSession.removeInstance(instance)
            }
        } message: { instance in
            if appSession.hasUnsyncedOutboxEntries(for: instance) {
                Text("This instance has unsynced changes that haven't uploaded yet. Forgetting it deletes its local data and sign-in permanently.")
            } else {
                Text("This deletes its local data and sign-in permanently. You'll need to sign in again to use it.")
            }
        }
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await appSession.signIn(serverURLString: serverURLString, username: username, password: password)
                await appSession.checkForLocalRecordsToImport()
                appSession.checkForOntologyPreloadPrompt()
            } catch {
                errorMessage = "Sign in failed: \(error.userFacingMessage)"
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
                await appSession.checkForLocalRecordsToImport()
                appSession.checkForOntologyPreloadPrompt()
            } catch {
                errorMessage = "ORCID sign in failed: \(error.userFacingMessage)"
            }
        }
    }
}
