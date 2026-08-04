import CupcakeNetworking
import SwiftUI

struct AccountSettingsView: View {
    @Environment(AppSession.self) private var appSession

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var currentPasswordForEmail = ""
    @State private var isEditingProfile = false
    @State private var isSavingProfile = false
    @State private var profileErrorMessage: String?

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isChangingPassword = false
    @State private var passwordErrorMessage: String?
    @State private var passwordChangedMessage: String?

    private var emailChanged: Bool {
        email.trimmingCharacters(in: .whitespaces) != (appSession.currentEmail ?? "")
    }

    var body: some View {
        Form {
            Section("Profile") {
                LabeledContent("Username", value: appSession.currentUsername ?? "—")
                if isEditingProfile {
                    TextField("First Name", text: $firstName)
                        .accessibilityIdentifier("accountFirstNameField")
                    TextField("Last Name", text: $lastName)
                        .accessibilityIdentifier("accountLastNameField")
                    TextField("Email", text: $email)
                        .accessibilityIdentifier("accountEmailField")
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    if emailChanged {
                        SecureField("Current Password (required to change email)", text: $currentPasswordForEmail)
                            .accessibilityIdentifier("accountCurrentPasswordForEmailField")
                    }
                    if let profileErrorMessage {
                        Text(profileErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Cancel") {
                            isEditingProfile = false
                            profileErrorMessage = nil
                        }
                        Spacer()
                        Button {
                            Task { await saveProfile() }
                        } label: {
                            if isSavingProfile {
                                ProgressView()
                            } else {
                                Text("Save")
                            }
                        }
                        .disabled(isSavingProfile)
                        .accessibilityIdentifier("saveAccountProfileButton")
                    }
                } else {
                    LabeledContent("First Name", value: appSession.currentFirstName?.isEmpty == false ? appSession.currentFirstName! : "—")
                    LabeledContent("Last Name", value: appSession.currentLastName?.isEmpty == false ? appSession.currentLastName! : "—")
                    LabeledContent("Email", value: appSession.currentEmail ?? "—")
                    Button("Edit Profile…") {
                        firstName = appSession.currentFirstName ?? ""
                        lastName = appSession.currentLastName ?? ""
                        email = appSession.currentEmail ?? ""
                        currentPasswordForEmail = ""
                        profileErrorMessage = nil
                        isEditingProfile = true
                    }
                    .accessibilityIdentifier("editAccountProfileButton")
                }
            }

            Section("Change Password") {
                SecureField("Current Password", text: $currentPassword)
                    .accessibilityIdentifier("accountCurrentPasswordField")
                SecureField("New Password", text: $newPassword)
                    .accessibilityIdentifier("accountNewPasswordField")
                SecureField("Confirm New Password", text: $confirmPassword)
                    .accessibilityIdentifier("accountConfirmPasswordField")
                if let passwordErrorMessage {
                    Text(passwordErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let passwordChangedMessage {
                    Text(passwordChangedMessage)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Button {
                    Task { await savePassword() }
                } label: {
                    if isChangingPassword {
                        ProgressView()
                    } else {
                        Text("Change Password")
                    }
                }
                .disabled(isChangingPassword || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty)
                .accessibilityIdentifier("changePasswordButton")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    Task { await appSession.signOut() }
                }
                .accessibilityIdentifier("signOutButton")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Account")
        .task {
            await appSession.refreshProfile()
        }
    }

    private func saveProfile() async {
        isSavingProfile = true
        defer { isSavingProfile = false }
        do {
            try await appSession.updateProfile(
                firstName: firstName,
                lastName: lastName,
                email: emailChanged ? email.trimmingCharacters(in: .whitespaces) : nil,
                currentPassword: emailChanged ? currentPasswordForEmail : nil
            )
            isEditingProfile = false
        } catch {
            profileErrorMessage = error.userFacingMessage
        }
    }

    private func savePassword() async {
        isChangingPassword = true
        defer { isChangingPassword = false }
        passwordErrorMessage = nil
        passwordChangedMessage = nil
        guard newPassword == confirmPassword else {
            passwordErrorMessage = "New passwords don't match."
            return
        }
        guard newPassword.count >= 8 else {
            passwordErrorMessage = "New password must be at least 8 characters."
            return
        }
        do {
            try await appSession.changePassword(currentPassword: currentPassword, newPassword: newPassword, confirmPassword: confirmPassword)
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            passwordChangedMessage = "Password changed successfully."
        } catch {
            passwordErrorMessage = error.userFacingMessage
        }
    }
}
