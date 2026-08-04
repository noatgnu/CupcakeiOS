import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct LabGroupPermissionsView: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    let labGroupServerID: Int64

    private struct EditablePermission {
        var canView: Bool
        var canInvite: Bool
        var canManage: Bool
        var canProcessJobs: Bool
    }

    @State private var members: [UserDTO] = []
    @State private var permissions: [Int64: EditablePermission] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if members.isEmpty {
                    ContentUnavailableView("No Members", systemImage: "person.2.slash", description: Text("This lab group has no direct members."))
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                            GridRow {
                                Text("Member").font(.caption.bold())
                                Text("View").font(.caption.bold())
                                Text("Invite").font(.caption.bold())
                                Text("Manage").font(.caption.bold())
                                Text("Process Jobs").font(.caption.bold())
                            }
                            Divider()
                            ForEach(members) { member in
                                GridRow {
                                    Text(member.username)
                                    Toggle("View", isOn: toggleBinding(userID: member.id, keyPath: \.canView))
                                        .labelsHidden()
                                        .accessibilityIdentifier("permissionToggle_\(member.username)_view")
                                    Toggle("Invite", isOn: toggleBinding(userID: member.id, keyPath: \.canInvite))
                                        .labelsHidden()
                                        .accessibilityIdentifier("permissionToggle_\(member.username)_invite")
                                    Toggle("Manage", isOn: toggleBinding(userID: member.id, keyPath: \.canManage))
                                        .labelsHidden()
                                        .accessibilityIdentifier("permissionToggle_\(member.username)_manage")
                                    Toggle("Process Jobs", isOn: toggleBinding(userID: member.id, keyPath: \.canProcessJobs))
                                        .labelsHidden()
                                        .accessibilityIdentifier("permissionToggle_\(member.username)_processJobs")
                                }
                                .accessibilityIdentifier("labGroupPermissionRow_\(member.username)")
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Manage Permissions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't update permission", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task {
                await load()
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
        #endif
    }

    private func permission(for userID: Int64) -> EditablePermission {
        permissions[userID] ?? EditablePermission(canView: false, canInvite: false, canManage: false, canProcessJobs: false)
    }

    private func toggleBinding(userID: Int64, keyPath: WritableKeyPath<EditablePermission, Bool>) -> Binding<Bool> {
        Binding(
            get: { permission(for: userID)[keyPath: keyPath] },
            set: { newValue in
                var updated = permission(for: userID)
                updated[keyPath: keyPath] = newValue
                permissions[userID] = updated
                Task { await save(userID: userID, permission: updated) }
            }
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let services = appSession.makeSyncServices()
            async let membersTask = services.labGroupSync.fetchMembers(labGroupServerID: labGroupServerID)
            async let permissionsTask = services.labGroupSync.fetchPermissions(labGroupServerID: labGroupServerID)
            let (fetchedMembers, fetchedPermissions) = try await (membersTask, permissionsTask)
            members = fetchedMembers
            permissions = Dictionary(uniqueKeysWithValues: fetchedPermissions.map {
                ($0.user, EditablePermission(canView: $0.canView, canInvite: $0.canInvite, canManage: $0.canManage, canProcessJobs: $0.canProcessJobs))
            })
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func save(userID: Int64, permission: EditablePermission) async {
        do {
            let services = appSession.makeSyncServices()
            try await services.labGroupSync.setPermission(
                userServerID: userID,
                labGroupServerID: labGroupServerID,
                canView: permission.canView,
                canInvite: permission.canInvite,
                canManage: permission.canManage,
                canProcessJobs: permission.canProcessJobs
            )
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
