import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct StaffAssignmentSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let jobClientID: UUID
    let jobServerID: Int64
    let labGroupServerID: Int64
    let initiallySelectedStaffIDs: Set<Int64>

    @State private var members: [UserDTO] = []
    @State private var selectedStaffIDs: Set<Int64>
    @State private var isLoadingMembers = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingPermissions = false
    @State private var searchText = ""

    private var filteredMembers: [UserDTO] {
        guard !searchText.isEmpty else { return members }
        return members.filter { $0.username.localizedCaseInsensitiveContains(searchText) }
    }

    init(jobClientID: UUID, jobServerID: Int64, labGroupServerID: Int64, initiallySelectedStaffIDs: Set<Int64>) {
        self.jobClientID = jobClientID
        self.jobServerID = jobServerID
        self.labGroupServerID = labGroupServerID
        self.initiallySelectedStaffIDs = initiallySelectedStaffIDs
        _selectedStaffIDs = State(initialValue: initiallySelectedStaffIDs)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isLoadingMembers {
                    ProgressView()
                } else if members.isEmpty {
                    Text("This lab group has no direct members.")
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Search members", text: $searchText)
                        .accessibilityIdentifier("staffMemberSearchField")
                    Section("Lab Group Members") {
                        ForEach(filteredMembers) { member in
                            Button {
                                toggle(member.id)
                            } label: {
                                HStack {
                                    Text(member.username)
                                    Spacer()
                                    if selectedStaffIDs.contains(member.id) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("staffMemberRow_\(member.username)")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Assign Staff")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem {
                    Button("Manage Permissions…") {
                        isShowingPermissions = true
                    }
                    .accessibilityIdentifier("managePermissionsButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                    .accessibilityIdentifier("saveStaffAssignmentButton")
                }
            }
            .alert("Couldn't assign staff", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $isShowingPermissions) {
                LabGroupPermissionsView(labGroupServerID: labGroupServerID)
            }
            .task {
                await loadMembers()
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }

    private func toggle(_ userID: Int64) {
        if selectedStaffIDs.contains(userID) {
            selectedStaffIDs.remove(userID)
        } else {
            selectedStaffIDs.insert(userID)
        }
    }

    private func loadMembers() async {
        isLoadingMembers = true
        defer { isLoadingMembers = false }
        do {
            let services = appSession.makeSyncServices()
            members = try await services.labGroupSync.fetchMembers(labGroupServerID: labGroupServerID)
        } catch {
            errorMessage = "Couldn't load lab group members: \(error.localizedDescription)"
            isShowingError = true
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.instrumentJobSync.updateStaff(jobServerID: jobServerID, staffServerIDs: Array(selectedStaffIDs))
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
