import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct AccessManagementView: View {
    enum Target {
        case protocolResource(serverID: Int64)
        case session(serverID: Int64)
    }

    private struct Grantee: Identifiable {
        let id: Int64
        let username: String
    }

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss
    let target: Target

    @State private var ownerUsername: String?
    @State private var editors: [Grantee] = []
    @State private var viewers: [Grantee] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    @State private var searchText = ""
    @State private var searchResults: [UserDTO] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Form {
                if let ownerUsername {
                    Section("Owner") {
                        Text(ownerUsername)
                    }
                }
                Section("Editors") {
                    if editors.isEmpty {
                        Text("No editors").foregroundStyle(.secondary)
                    }
                    ForEach(editors) { editor in
                        HStack {
                            Text(editor.username)
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await removeEditor(editor) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("removeEditorButton_\(editor.username)")
                        }
                        .accessibilityIdentifier("editorRow_\(editor.username)")
                    }
                }
                Section("Viewers") {
                    if viewers.isEmpty {
                        Text("No viewers").foregroundStyle(.secondary)
                    }
                    ForEach(viewers) { viewer in
                        HStack {
                            Text(viewer.username)
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                Task { await removeViewer(viewer) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("removeViewerButton_\(viewer.username)")
                        }
                        .accessibilityIdentifier("viewerRow_\(viewer.username)")
                    }
                }
                Section("Add Person") {
                    TextField("Search users…", text: $searchText)
                        .accessibilityIdentifier("accessSearchUsersField")
                    if isSearching {
                        ProgressView()
                    } else {
                        ForEach(searchResults) { user in
                            HStack {
                                Text(user.username)
                                    .lineLimit(1)
                                Spacer()
                                Button("Editor") {
                                    Task { await addUser(user, as: .editor) }
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("addAsEditorButton_\(user.username)")
                                Button("Viewer") {
                                    Task { await addUser(user, as: .viewer) }
                                }
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("addAsViewerButton_\(user.username)")
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Manage Access")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't update access", isPresented: $isShowingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await load() }
            .task(id: searchText) {
                guard !searchText.isEmpty else {
                    searchResults = []
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                isSearching = true
                defer { isSearching = false }
                searchResults = (try? await appSession.makeSyncServices().userProfileSync.searchUsers(query: searchText)) ?? []
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private enum Role {
        case editor
        case viewer
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            switch target {
            case .protocolResource(let serverID):
                let dto = try await appSession.makeSyncServices().protocolSync.fetchDetail(serverID: serverID)
                apply(ownerUsername: dto.ownerUsername, editorIDs: dto.editors, editorUsernames: dto.editorsUsernames, viewerIDs: dto.viewers, viewerUsernames: dto.viewersUsernames)
            case .session(let serverID):
                let dto = try await appSession.makeSyncServices().sessionSync.fetchDetail(serverID: serverID)
                apply(ownerUsername: dto.ownerUsername, editorIDs: dto.editors, editorUsernames: dto.editorsUsernames, viewerIDs: dto.viewers, viewerUsernames: dto.viewersUsernames)
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func apply(ownerUsername: String?, editorIDs: [Int64], editorUsernames: [String], viewerIDs: [Int64], viewerUsernames: [String]) {
        self.ownerUsername = ownerUsername
        editors = zip(editorIDs, editorUsernames).map { Grantee(id: $0, username: $1) }
        viewers = zip(viewerIDs, viewerUsernames).map { Grantee(id: $0, username: $1) }
    }

    private func addUser(_ user: UserDTO, as role: Role) async {
        var updatedEditors = editors.map(\.id)
        var updatedViewers = viewers.map(\.id)
        switch role {
        case .editor:
            updatedViewers.removeAll { $0 == user.id }
            if !updatedEditors.contains(user.id) { updatedEditors.append(user.id) }
        case .viewer:
            updatedEditors.removeAll { $0 == user.id }
            if !updatedViewers.contains(user.id) { updatedViewers.append(user.id) }
        }
        await save(editors: updatedEditors, viewers: updatedViewers)
        searchText = ""
        searchResults = []
    }

    private func removeEditor(_ editor: Grantee) async {
        let updatedEditors = editors.map(\.id).filter { $0 != editor.id }
        await save(editors: updatedEditors, viewers: viewers.map(\.id))
    }

    private func removeViewer(_ viewer: Grantee) async {
        let updatedViewers = viewers.map(\.id).filter { $0 != viewer.id }
        await save(editors: editors.map(\.id), viewers: updatedViewers)
    }

    private func save(editors editorIDs: [Int64], viewers viewerIDs: [Int64]) async {
        isSaving = true
        defer { isSaving = false }
        do {
            switch target {
            case .protocolResource(let serverID):
                let dto = try await appSession.makeSyncServices().protocolSync.updateAccess(serverID: serverID, editors: editorIDs, viewers: viewerIDs)
                apply(ownerUsername: dto.ownerUsername, editorIDs: dto.editors, editorUsernames: dto.editorsUsernames, viewerIDs: dto.viewers, viewerUsernames: dto.viewersUsernames)
            case .session(let serverID):
                let dto = try await appSession.makeSyncServices().sessionSync.updateAccess(serverID: serverID, editors: editorIDs, viewers: viewerIDs)
                apply(ownerUsername: dto.ownerUsername, editorIDs: dto.editors, editorUsernames: dto.editorsUsernames, viewerIDs: dto.viewers, viewerUsernames: dto.viewersUsernames)
            }
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
