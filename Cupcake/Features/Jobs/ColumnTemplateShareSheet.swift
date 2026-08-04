import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct ColumnTemplateShareSheet: View {
    let template: MetadataColumnTemplateDTO

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    @State private var shares: [MetadataColumnTemplateShareDTO] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingError = false

    @State private var searchText = ""
    @State private var searchResults: [UserDTO] = []
    @State private var isSearching = false

    private static let permissionLevels: [(value: String, label: String)] = [
        ("view", "View"),
        ("use", "Use"),
        ("edit", "Edit"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Shared With") {
                    if shares.isEmpty {
                        Text(isLoading ? "Loading…" : "Not shared with anyone yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shares) { existingShare in
                        shareRow(existingShare)
                    }
                }
                Section("Add Person") {
                    TextField("Search users…", text: $searchText)
                        .accessibilityIdentifier("templateShareSearchUsersField")
                    if isSearching {
                        ProgressView()
                    } else {
                        ForEach(searchResults) { user in
                            HStack {
                                Text(user.username)
                                    .lineLimit(1)
                                Spacer()
                                ForEach(Self.permissionLevels, id: \.value) { level in
                                    Button(level.label) {
                                        Task { await share(userID: user.id, permissionLevel: level.value) }
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityIdentifier("shareTemplateAs\(level.label)Button_\(user.username)")
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Share \"\(template.name)\"")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Couldn't update sharing", isPresented: $isShowingError) {
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

    @ViewBuilder
    private func shareRow(_ existingShare: MetadataColumnTemplateShareDTO) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(existingShare.userUsername)
                    .lineLimit(1)
                Text(permissionLevelLabel(for: existingShare.permissionLevel))
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(Self.permissionLevels, id: \.value) { level in
                    Button(level.label) {
                        Task { await share(userID: existingShare.user, permissionLevel: level.value) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityIdentifier("changeTemplateSharePermissionMenu_\(existingShare.userUsername)")
            Button(role: .destructive) {
                Task { await unshare(userID: existingShare.user) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("removeTemplateShareButton_\(existingShare.userUsername)")
        }
        .accessibilityIdentifier("templateShareRow_\(existingShare.userUsername)")
    }

    private func permissionLevelLabel(for value: String) -> String {
        for level in Self.permissionLevels where level.value == value {
            return level.label
        }
        return value
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            shares = try await appSession.makeSyncServices().metadataColumnTemplateSync.fetchShares(templateServerID: template.id)
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func share(userID: Int64, permissionLevel: String) async {
        do {
            try await appSession.makeSyncServices().metadataColumnTemplateSync.shareTemplate(
                templateServerID: template.id, userID: userID, permissionLevel: permissionLevel
            )
            searchText = ""
            searchResults = []
            await load()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func unshare(userID: Int64) async {
        do {
            try await appSession.makeSyncServices().metadataColumnTemplateSync.unshareTemplate(templateServerID: template.id, userID: userID)
            await load()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
