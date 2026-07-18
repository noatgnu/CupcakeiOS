import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct EditStorageLocationSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let existingObject: CachedStorageObject?
    let parentServerID: Int64?

    private static let typeOptions = ["shelf", "box", "fridge", "freezer", "room", "building", "floor", "other"]

    @State private var objectName: String
    @State private var objectType: String
    @State private var objectDescription: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    init(existingObject: CachedStorageObject? = nil, parentServerID: Int64? = nil) {
        self.existingObject = existingObject
        self.parentServerID = parentServerID
        _objectName = State(initialValue: existingObject?.objectName ?? "")
        _objectType = State(initialValue: existingObject?.objectType ?? "shelf")
        _objectDescription = State(initialValue: existingObject?.objectDescription ?? "")
    }

    private var isEditing: Bool { existingObject != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $objectName)
                    .accessibilityIdentifier("storageLocationNameField")
                Picker("Type", selection: $objectType) {
                    ForEach(Self.typeOptions, id: \.self) { option in
                        Text(option.capitalized).tag(option)
                    }
                }
                .accessibilityIdentifier("storageLocationTypePicker")
                TextField("Description", text: $objectDescription, axis: .vertical)
                    .accessibilityIdentifier("storageLocationDescriptionField")
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Location" : "New Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        Task { await save() }
                    }
                    .disabled(objectName.isEmpty || isSaving)
                    .accessibilityIdentifier("saveStorageLocationButton")
                }
            }
        }
        .frame(minWidth: 320, minHeight: 260)
        .alert(isEditing ? "Couldn't save location" : "Couldn't create location", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let description = objectDescription.isEmpty ? nil : objectDescription
        do {
            if let existingObject {
                try await appSession.makeSyncServices().inventorySync.updateStorageObject(
                    serverID: existingObject.serverID,
                    objectName: objectName,
                    objectType: objectType,
                    objectDescription: description
                )
            } else {
                try await appSession.makeSyncServices().inventorySync.createStorageObject(
                    objectName: objectName,
                    objectType: objectType,
                    objectDescription: description,
                    storedAt: parentServerID
                )
            }
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
