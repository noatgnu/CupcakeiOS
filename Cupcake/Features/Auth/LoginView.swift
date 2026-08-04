import CupcakeModels
import CupcakeNetworking
import SwiftUI

struct LoginView: View {
    @Environment(AppSession.self) private var appSession
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    @State private var serverURLString = "https://cupcake.proteo.info/api/v1/"
    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var instancePendingRemoval: KnownInstance?
    @State private var instancePendingWindowChoice: KnownInstance?
    @State private var isShowingSignInWindowChoice = false
    @State private var isShowingORCIDWindowChoice = false
    @State private var isShowingContinueOfflineWindowChoice = false

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
                            #if os(macOS)
                            if NamespaceRegistry.shared.hasOtherOpenMainWindows {
                                instancePendingWindowChoice = instance
                            } else {
                                appSession.switchToInstance(instance)
                            }
                            #else
                            appSession.switchToInstance(instance)
                            #endif
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
                    #if os(macOS)
                    if NamespaceRegistry.shared.hasOtherOpenMainWindows {
                        isShowingSignInWindowChoice = true
                    } else {
                        signIn()
                    }
                    #else
                    signIn()
                    #endif
                } label: {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign In")
                    }
                }
                .disabled(isSigningIn || serverURLString.isEmpty || username.isEmpty || password.isEmpty)
                .accessibilityIdentifier("signInButton")
                #if os(macOS)
                .confirmationDialog("Open This Instance", isPresented: $isShowingSignInWindowChoice) {
                    Button("Open Here") { signIn() }
                    Button("Open in New Window") { openSignInInNewWindow() }
                    Button("Cancel", role: .cancel) {}
                }
                #endif
            }
            Section {
                Button {
                    #if os(macOS)
                    if NamespaceRegistry.shared.hasOtherOpenMainWindows {
                        isShowingORCIDWindowChoice = true
                    } else {
                        signInWithORCID()
                    }
                    #else
                    signInWithORCID()
                    #endif
                } label: {
                    if isSigningIn {
                        ProgressView()
                    } else {
                        Text("Sign in with ORCID")
                    }
                }
                .disabled(isSigningIn || serverURLString.isEmpty)
                .accessibilityIdentifier("signInWithOrcidButton")
                #if os(macOS)
                .confirmationDialog("Open This Instance", isPresented: $isShowingORCIDWindowChoice) {
                    Button("Open Here") { signInWithORCID() }
                    Button("Open in New Window") { openORCIDInNewWindow() }
                    Button("Cancel", role: .cancel) {}
                }
                #endif
            }
            Section {
                Button("Continue Offline") {
                    #if os(macOS)
                    if NamespaceRegistry.shared.hasOtherOpenMainWindows {
                        isShowingContinueOfflineWindowChoice = true
                    } else {
                        appSession.continueOffline()
                        appSession.checkForOntologyPreloadPrompt()
                    }
                    #else
                    appSession.continueOffline()
                    appSession.checkForOntologyPreloadPrompt()
                    #endif
                }
                .disabled(isSigningIn)
                .accessibilityIdentifier("continueOfflineButton")
                #if os(macOS)
                .confirmationDialog("Open Offline Notebook", isPresented: $isShowingContinueOfflineWindowChoice) {
                    Button("Open Here") {
                        appSession.continueOffline()
                        appSession.checkForOntologyPreloadPrompt()
                    }
                    Button("Open in New Window") { openContinueOfflineInNewWindow() }
                    Button("Cancel", role: .cancel) {}
                }
                #endif
            } footer: {
                Text("Use Cupcake as a personal, local-only lab notebook with no server. Everything you create stays on this device until you sign in later.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Cupcake")
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 320)
        #endif
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
        #if os(macOS)
        .confirmationDialog(
            "Open \(instancePendingWindowChoice?.label ?? "")",
            isPresented: Binding(
                get: { instancePendingWindowChoice != nil },
                set: { if !$0 { instancePendingWindowChoice = nil } }
            ),
            presenting: instancePendingWindowChoice
        ) { instance in
            Button("Open Here") { appSession.switchToInstance(instance) }
            Button("Open in New Window") { openKnownInstanceInNewWindow(instance) }
            Button("Cancel", role: .cancel) {}
        }
        #endif
    }

    #if os(macOS)
    private func openKnownInstanceInNewWindow(_ instance: KnownInstance) {
        NamespaceRegistry.shared.enqueuePendingLaunchAction(.knownInstance(instance))
        openWindow(id: "main")
    }

    private func openSignInInNewWindow() {
        NamespaceRegistry.shared.enqueuePendingLaunchAction(.signIn(serverURLString: serverURLString, username: username, password: password))
        openWindow(id: "main")
    }

    private func openORCIDInNewWindow() {
        NamespaceRegistry.shared.enqueuePendingLaunchAction(.signInWithORCID(serverURLString: serverURLString))
        openWindow(id: "main")
    }

    private func openContinueOfflineInNewWindow() {
        NamespaceRegistry.shared.enqueuePendingLaunchAction(.continueOffline)
        openWindow(id: "main")
    }
    #endif

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
