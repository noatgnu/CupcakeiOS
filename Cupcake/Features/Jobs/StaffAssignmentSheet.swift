import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

/// Staff candidates are the job's already-assigned lab group's own direct members — not a global
/// user search (there's no such endpoint the reference web app uses for this; confirmed against
/// `job-submission-state.ts`, which populates its own staff list from `getLabGroupMembers`, not a
/// `/users/` search). Selecting a member who lacks `can_process_jobs` for that lab group is a
/// real, expected rejection, not a bug — the server validates this at save time
/// (`InstrumentJobSerializer.validate`) and this sheet surfaces that message verbatim rather than
/// a generic "couldn't sync", since it names exactly which users are the problem.
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
                    Section("Lab Group Members") {
                        ForEach(members) { member in
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
            // A validation rejection here names exactly which users lack direct membership or
            // `can_process_jobs` — `userFacingMessage` surfaces that verbatim rather than a
            // generic "couldn't sync" message.
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
