import CupcakeAuth
import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct DeviceTokensView: View {
    @Environment(AppSession.self) private var appSession

    @State private var tokens: [DeviceTokenDTO] = []
    @State private var totalCount = 0
    @State private var offset = 0
    private let pageSize = 25
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var isShowingNewTokenSheet = false
    @State private var revealedTokenIDs: Set<Int> = []
    @State private var pendingDeleteToken: DeviceTokenDTO?

    var body: some View {
        List {
            if tokens.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text("No API tokens found.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Tokens (\(totalCount))") {
                    ForEach(tokens) { token in
                        tokenRow(token)
                    }
                }
                if totalCount > pageSize {
                    paginationControls
                }
            }
        }
        .navigationTitle("API Tokens")
        .toolbar {
            ToolbarItem {
                Button {
                    isShowingNewTokenSheet = true
                } label: {
                    Label("New Token", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .accessibilityIdentifier("newDeviceTokenButton")
            }
        }
        .sheet(isPresented: $isShowingNewTokenSheet) {
            NewDeviceTokenSheet(onCreated: {
                offset = 0
                Task { await reload() }
            })
        }
        .alert("This is your current device's token", isPresented: Binding(
            get: { pendingDeleteToken != nil },
            set: { if !$0 { pendingDeleteToken = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDeleteToken = nil }
            Button("Delete Anyway", role: .destructive) {
                if let pendingDeleteToken {
                    Task { await delete(pendingDeleteToken) }
                }
            }
        } message: {
            Text("Deleting this token will sign this device out immediately.")
        }
        .alert("Something went wrong", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await reload()
        }
    }

    private func isThisDevice(_ token: DeviceTokenDTO) -> Bool {
        appSession.deviceToken == token.token
    }

    @ViewBuilder
    private func tokenRow(_ token: DeviceTokenDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(token.label)
                    .fontWeight(.semibold)
                if isThisDevice(token) {
                    Text("This Device")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .clipShape(Capsule())
                }
                if !token.enabled {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if token.isExpired {
                    Text("Expired")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            Text(revealedTokenIDs.contains(token.id) ? token.token : String(repeating: "•", count: 24))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .onTapGesture {
                    if revealedTokenIDs.contains(token.id) {
                        revealedTokenIDs.remove(token.id)
                    } else {
                        revealedTokenIDs.insert(token.id)
                    }
                }
            Text("\(token.permission.capitalized) · Last used: \(token.lastUsedAt ?? "never")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("deviceTokenRow_\(token.label)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                if isThisDevice(token) {
                    pendingDeleteToken = token
                } else {
                    Task { await delete(token) }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            Button {
                Task { await toggle(token) }
            } label: {
                Label(token.enabled ? "Disable" : "Enable", systemImage: token.enabled ? "pause.circle" : "play.circle")
            }
            .tint(.orange)
            Button {
                Task { await rotate(token) }
            } label: {
                Label("Rotate", systemImage: "arrow.triangle.2.circlepath")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                Task { await rotate(token) }
            } label: {
                Label("Rotate", systemImage: "arrow.triangle.2.circlepath")
            }
            Button {
                Task { await toggle(token) }
            } label: {
                Label(token.enabled ? "Disable" : "Enable", systemImage: token.enabled ? "pause.circle" : "play.circle")
            }
            Button(role: .destructive) {
                if isThisDevice(token) {
                    pendingDeleteToken = token
                } else {
                    Task { await delete(token) }
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var paginationControls: some View {
        HStack {
            Button("Previous") {
                offset = max(0, offset - pageSize)
                Task { await reload() }
            }
            .disabled(offset == 0)
            .accessibilityIdentifier("deviceTokensPreviousPageButton")
            Spacer()
            Text("\(min(offset + 1, totalCount))-\(min(offset + tokens.count, totalCount)) of \(totalCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Next") {
                offset += pageSize
                Task { await reload() }
            }
            .disabled(offset + pageSize >= totalCount)
            .accessibilityIdentifier("deviceTokensNextPageButton")
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await appSession.makeSyncServices().deviceTokenSync.fetchPage(offset: offset, limit: pageSize)
            tokens = page.results
            totalCount = page.count
        } catch {
            tokens = []
        }
    }

    private func rotate(_ token: DeviceTokenDTO) async {
        do {
            try await appSession.makeSyncServices().deviceTokenSync.rotate(id: token.id)
            await reload()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func toggle(_ token: DeviceTokenDTO) async {
        do {
            try await appSession.makeSyncServices().deviceTokenSync.toggle(id: token.id)
            await reload()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func delete(_ token: DeviceTokenDTO) async {
        do {
            try await appSession.makeSyncServices().deviceTokenSync.delete(id: token.id)
            pendingDeleteToken = nil
            await reload()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

private struct NewDeviceTokenSheet: View {
    let onCreated: () -> Void

    @Environment(AppSession.self) private var appSession
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var description = ""
    @State private var permission = "write"
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var createdToken: String?

    var body: some View {
        NavigationStack {
            Form {
                if let createdToken {
                    Section("Token Created") {
                        Text(createdToken)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Text("Copy this now — you won't be able to see it again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Details") {
                        TextField("Label", text: $label)
                            .accessibilityIdentifier("newDeviceTokenLabelField")
                        TextField("Description (optional)", text: $description)
                            .accessibilityIdentifier("newDeviceTokenDescriptionField")
                        Picker("Permission", selection: $permission) {
                            Text("Read").tag("read")
                            Text("Write").tag("write")
                        }
                        .accessibilityIdentifier("newDeviceTokenPermissionPicker")
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New API Token")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdToken == nil ? "Cancel" : "Done") { dismiss() }
                }
                if createdToken == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await create() }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Create")
                            }
                        }
                        .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                        .accessibilityIdentifier("createDeviceTokenButton")
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
        #endif
    }

    private func create() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let dto = try await appSession.makeSyncServices().deviceTokenSync.create(
                label: label,
                description: description,
                permission: permission
            )
            createdToken = dto.token
            onCreated()
        } catch {
            errorMessage = error.userFacingMessage
        }
    }
}
