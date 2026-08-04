import CupcakeNetworking
import CupcakeSync
import CupcakeTranscription
import SwiftUI

struct SessionAnnotationFoldersView: View {
    @Environment(AppSession.self) private var appSession

    let sessionServerID: Int64

    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "Session")]
    @State private var childFolders: [AnnotationFolderDTO] = []
    @State private var annotations: [AnnotationSummaryDTO] = []
    @State private var isLoading = false
    @State private var isShowingNewFolderAlert = false
    @State private var isShowingNewNoteSheet = false
    @State private var newFolderName = ""
    @State private var newNoteText = ""
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var renamingFolder: AnnotationFolderDTO?
    @State private var renameText = ""
    @State private var movingFolder: AnnotationFolderDTO?

    private var currentFolderID: Int64? {
        pathStack.last?.id
    }

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack) {
            ExplorerList(isEmpty: childFolders.isEmpty) {
                if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No Subfolders",
                        systemImage: "folder",
                        description: Text("This folder has no subfolders.")
                    )
                }
            } rows: {
                ForEach(childFolders) { folder in
                    Button {
                        enterFolder(folder)
                    } label: {
                        Label(folder.folderName, systemImage: "folder")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("annotationFolderRow_\(folder.folderName)")
                    .contextMenu {
                        Button {
                            renameText = folder.folderName
                            renamingFolder = folder
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button {
                            movingFolder = folder
                        } label: {
                            Label("Move…", systemImage: "folder")
                        }
                    }
                }
            }
        } detail: {
            ExplorerList(isEmpty: annotations.isEmpty) {
                if isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("This folder has no notes.")
                    )
                }
            } rows: {
                ForEach(annotations) { annotation in
                    if annotation.annotationType == "audio" {
                        Label(annotation.transcription.map(WebVTTFormatter.extractPlainText) ?? "Audio note", systemImage: "waveform")
                    } else {
                        Text(annotation.annotation)
                    }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button {
                        newFolderName = ""
                        isShowingNewFolderAlert = true
                    } label: {
                        Label("New Folder", systemImage: "folder.badge.plus")
                    }
                    .accessibilityIdentifier("newAnnotationFolderButton")
                }
                ToolbarItem {
                    Button {
                        newNoteText = ""
                        isShowingNewNoteSheet = true
                    } label: {
                        Label("New Note", systemImage: "note.text.badge.plus")
                    }
                    .accessibilityIdentifier("newFolderNoteButton")
                    .disabled(currentFolderID == nil)
                }
            }
        }
        .alert("New Folder", isPresented: $isShowingNewFolderAlert) {
            TextField("Folder Name", text: $newFolderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                Task { await createFolder() }
            }
        }
        .alert("Rename Folder", isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
            TextField("Folder Name", text: $renameText)
                .accessibilityIdentifier("renameAnnotationFolderField")
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Rename") {
                Task { await renameFolder() }
            }
        }
        .sheet(item: $movingFolder) { folder in
            MoveAnnotationFolderSheet(sessionServerID: sessionServerID, folderToMove: folder) {
                await load()
            }
        }
        .sheet(isPresented: $isShowingNewNoteSheet) {
            NavigationStack {
                Form {
                    TextField("Note", text: $newNoteText, axis: .vertical)
                        .lineLimit(5...10)
                        .accessibilityIdentifier("newFolderNoteTextField")
                }
                .navigationTitle("New Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isShowingNewNoteSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { await createNote() }
                        }
                        .disabled(newNoteText.isEmpty)
                        .accessibilityIdentifier("saveFolderNoteButton")
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 320, minHeight: 200)
            #endif
        }
        .alert("Something went wrong", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task(id: currentFolderID) {
            await load()
        }
    }

    private func enterFolder(_ folder: AnnotationFolderDTO) {
        pathStack.append(BreadcrumbSegment(id: folder.id, name: folder.folderName))
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let services = appSession.makeSyncServices()
            if let currentFolderID {
                let response = try await services.annotationFolderSync.fetchChildren(folderServerID: currentFolderID)
                childFolders = response.folders
                annotations = response.annotations
            } else {
                childFolders = try await services.annotationFolderSync.fetchRootFolders(sessionServerID: sessionServerID)
                annotations = []
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func renameFolder() async {
        guard let renamingFolder, !renameText.isEmpty else { return }
        do {
            let services = appSession.makeSyncServices()
            try await services.annotationFolderSync.renameFolder(folderServerID: renamingFolder.id, folderName: renameText)
            self.renamingFolder = nil
            await load()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func createFolder() async {
        guard !newFolderName.isEmpty else { return }
        do {
            let services = appSession.makeSyncServices()
            if let currentFolderID {
                try await services.annotationFolderSync.createSubfolder(parentFolderServerID: currentFolderID, folderName: newFolderName)
            } else {
                try await services.annotationFolderSync.createRootFolder(sessionServerID: sessionServerID, folderName: newFolderName)
            }
            await load()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func createNote() async {
        guard let currentFolderID, !newNoteText.isEmpty else { return }
        do {
            let services = appSession.makeSyncServices()
            try await services.annotationFolderSync.createTextAnnotation(folderServerID: currentFolderID, text: newNoteText)
            isShowingNewNoteSheet = false
            await load()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
