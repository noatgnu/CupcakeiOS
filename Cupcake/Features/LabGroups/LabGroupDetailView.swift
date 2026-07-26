import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct LabGroupDetailView: View {
    let labGroupServerID: Int64

    @Environment(AppSession.self) private var appSession
    @Query private var groups: [CachedLabGroup]

    @State private var members: [UserDTO] = []
    @State private var isLoadingMembers = false
    @State private var isShowingInviteSheet = false
    @State private var isShowingEditSheet = false
    @State private var inviteEmail = ""
    @State private var inviteMessage = ""
    @State private var isSendingInvite = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var group: CachedLabGroup? {
        groups.first(where: { $0.serverID == labGroupServerID })
    }

    init(labGroupServerID: Int64) {
        self.labGroupServerID = labGroupServerID
        let id = labGroupServerID
        _groups = Query(filter: #Predicate<CachedLabGroup> { $0.serverID == id })
    }

    var body: some View {
        Group {
            if let group {
                List {
                    Section("Details") {
                        LabeledContent("Name", value: group.name)
                        if let description = group.groupDescription, !description.isEmpty {
                            LabeledContent("Description", value: description)
                        }
                        LabeledContent("Members", value: "\(group.memberCount)")
                        LabeledContent("Sub-groups", value: "\(group.subGroupsCount)")
                        LabeledContent("Allows Member Invites", value: group.allowMemberInvites ? "Yes" : "No")
                        LabeledContent("Allows Job Processing", value: group.allowProcessJobs ? "Yes" : "No")
                    }

                    Section("Members") {
                        if isLoadingMembers {
                            ProgressView()
                        } else if members.isEmpty {
                            Text("No direct members found.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(members) { member in
                                Text(member.username)
                                    .accessibilityIdentifier("labGroupMemberRow_\(member.username)")
                                    .swipeActions(edge: .trailing) {
                                        if group.canManage {
                                            Button(role: .destructive) {
                                                Task { await removeMember(member) }
                                            } label: {
                                                Label("Remove", systemImage: "person.badge.minus")
                                            }
                                        }
                                    }
                                    .contextMenu {
                                        if group.canManage {
                                            Button(role: .destructive) {
                                                Task { await removeMember(member) }
                                            } label: {
                                                Label("Remove", systemImage: "person.badge.minus")
                                            }
                                        }
                                    }
                            }
                        }
                        if group.canInvite {
                            Button {
                                inviteEmail = ""
                                inviteMessage = ""
                                isShowingInviteSheet = true
                            } label: {
                                Label("Invite Member…", systemImage: "person.badge.plus")
                            }
                            .accessibilityIdentifier("inviteMemberButton")
                        }
                    }

                    if !group.isCreator && group.isMember {
                        Section {
                            Button("Leave Lab Group", role: .destructive) {
                                Task { await leave() }
                            }
                            .accessibilityIdentifier("leaveLabGroupButton")
                        }
                    }
                }
                .navigationTitle(group.name)
                .toolbar {
                    if group.canManage {
                        ToolbarItem {
                            Button {
                                isShowingEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .accessibilityIdentifier("editLabGroupButton")
                        }
                    }
                }
                .task(id: labGroupServerID) {
                    await loadMembers()
                }
                .sheet(isPresented: $isShowingInviteSheet) {
                    inviteSheet
                }
                .sheet(isPresented: $isShowingEditSheet) {
                    NewLabGroupSheet(existingGroup: group)
                }
                .alert("Something went wrong", isPresented: $isShowingError) {
                    Button("OK") {}
                } message: {
                    Text(errorMessage ?? "")
                }
            } else {
                ContentUnavailableView("Lab Group Not Found", systemImage: "person.3")
            }
        }
    }

    private var inviteSheet: some View {
        NavigationStack {
            Form {
                Section("Invite by Email") {
                    TextField("Email", text: $inviteEmail)
                        .accessibilityIdentifier("inviteEmailField")
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    TextField("Message (optional)", text: $inviteMessage, axis: .vertical)
                        .accessibilityIdentifier("inviteMessageField")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Invite Member")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isShowingInviteSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await sendInvite() }
                    } label: {
                        if isSendingInvite {
                            ProgressView()
                        } else {
                            Text("Invite")
                        }
                    }
                    .disabled(inviteEmail.trimmingCharacters(in: .whitespaces).isEmpty || isSendingInvite)
                    .accessibilityIdentifier("sendInviteButton")
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
    }

    private func loadMembers() async {
        isLoadingMembers = true
        defer { isLoadingMembers = false }
        do {
            members = try await appSession.makeSyncServices().labGroupSync.fetchMembers(labGroupServerID: labGroupServerID)
        } catch {
            members = []
        }
    }

    private func sendInvite() async {
        isSendingInvite = true
        defer { isSendingInvite = false }
        do {
            try await appSession.makeSyncServices().labGroupSync.inviteUser(
                labGroupServerID: labGroupServerID,
                email: inviteEmail.trimmingCharacters(in: .whitespaces),
                message: inviteMessage.isEmpty ? nil : inviteMessage
            )
            isShowingInviteSheet = false
        } catch {
            errorMessage = error.userFacingMessage
        }
    }

    private func removeMember(_ member: UserDTO) async {
        do {
            try await appSession.makeSyncServices().labGroupSync.removeMember(labGroupServerID: labGroupServerID, userServerID: member.id)
            await loadMembers()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func leave() async {
        do {
            try await appSession.makeSyncServices().labGroupSync.leaveGroup(labGroupServerID: labGroupServerID)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
