import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct PendingInvitationsView: View {
    @Environment(AppSession.self) private var appSession

    @State private var invitations: [LabGroupInvitationDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        Group {
            if isLoading && invitations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if invitations.isEmpty {
                ContentUnavailableView("No Pending Invitations", systemImage: "envelope", description: Text("Lab group invitations sent to your account's email will appear here."))
            } else {
                List {
                    ForEach(invitations) { invitation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(invitation.labGroupName)
                                .font(.headline)
                            Text("Invited by \(invitation.inviterName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let message = invitation.message, !message.isEmpty {
                                Text(message)
                                    .font(.caption)
                            }
                            HStack {
                                Button("Accept") {
                                    Task { await respond(invitation, accept: true) }
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("acceptInvitationButton_\(invitation.id)")

                                Button("Decline", role: .destructive) {
                                    Task { await respond(invitation, accept: false) }
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("declineInvitationButton_\(invitation.id)")
                            }
                            .padding(.top, 2)
                        }
                        .accessibilityIdentifier("pendingInvitationRow_\(invitation.labGroupName)")
                    }
                }
            }
        }
        .navigationTitle("Invitations")
        .task {
            await loadInvitations()
        }
        .alert("Couldn't respond to invitation", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadInvitations() async {
        isLoading = true
        defer { isLoading = false }
        do {
            invitations = try await appSession.makeSyncServices().labGroupSync.fetchMyPendingInvitations()
        } catch {
            invitations = []
        }
    }

    private func respond(_ invitation: LabGroupInvitationDTO, accept: Bool) async {
        do {
            if accept {
                try await appSession.makeSyncServices().labGroupSync.acceptInvitation(id: invitation.id)
                try? await appSession.makeSyncServices().labGroupSync.refetchAll()
            } else {
                try await appSession.makeSyncServices().labGroupSync.rejectInvitation(id: invitation.id)
            }
            await loadInvitations()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
