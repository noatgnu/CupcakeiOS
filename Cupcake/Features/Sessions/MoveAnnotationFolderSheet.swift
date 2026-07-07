import CupcakeNetworking
import CupcakeSync
import SwiftUI

/// Drill-down folder picker for moving a folder to a new parent, excluding the folder itself.
struct MoveAnnotationFolderSheet: View {
    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    let sessionServerID: Int64
    let folderToMove: AnnotationFolderDTO
    let onMoved: () async -> Void

    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "Session")]
    @State private var folders: [AnnotationFolderDTO] = []
    @State private var isLoading = false
    @State private var isMoving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    private var currentFolderID: Int64? {
        pathStack.last?.id
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await move(to: currentFolderID) }
                    } label: {
                        Label("Move Here", systemImage: "checkmark.circle")
                    }
                    .disabled(isMoving)
                    .accessibilityIdentifier("moveFolderHereButton")
                }
                Section {
                    if isLoading {
                        ProgressView()
                    } else if folders.isEmpty {
                        Text("No subfolders")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(folders) { folder in
                            if folder.id == folderToMove.id {
                                Label(folder.folderName, systemImage: "folder")
                                    .foregroundStyle(.tertiary)
                            } else {
                                Button {
                                    pathStack.append(BreadcrumbSegment(id: folder.id, name: folder.folderName))
                                } label: {
                                    Label(folder.folderName, systemImage: "folder")
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("moveFolderDestinationRow_\(folder.folderName)")
                            }
                        }
                    }
                }
            }
            .navigationTitle(pathStack.last?.name ?? "Move Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if pathStack.count > 1 {
                    ToolbarItem(placement: .navigation) {
                        Button("Back") { pathStack.removeLast() }
                    }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 400)
        .alert("Couldn't move folder", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: currentFolderID) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let services = appSession.makeSyncServices()
            if let currentFolderID {
                let response = try await services.annotationFolderSync.fetchChildren(folderServerID: currentFolderID)
                folders = response.folders
            } else {
                folders = try await services.annotationFolderSync.fetchRootFolders(sessionServerID: sessionServerID)
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func move(to newParentServerID: Int64?) async {
        isMoving = true
        defer { isMoving = false }
        do {
            let services = appSession.makeSyncServices()
            try await services.annotationFolderSync.moveFolder(folderServerID: folderToMove.id, newParentServerID: newParentServerID)
            await onMoved()
            dismiss()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
