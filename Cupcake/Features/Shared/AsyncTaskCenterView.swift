import CupcakeNetworking
import CupcakeSync
import SwiftUI

struct AsyncTaskCenterView: View {
    @Environment(AppSession.self) private var appSession

    @State private var tasks: [AsyncTaskDTO] = []
    @State private var totalCount = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var downloadingTaskID: String?
    @State private var downloadedFileURL: URL?

    private static let statusOptions = ["All", "QUEUED", "STARTED", "SUCCESS", "FAILURE", "CANCELLED"]
    @State private var statusFilter = "All"

    private var filteredTasks: [AsyncTaskDTO] {
        statusFilter == "All" ? tasks : tasks.filter { $0.status == statusFilter }
    }

    var body: some View {
        List {
            if filteredTasks.isEmpty {
                if isLoading {
                    ProgressView()
                } else {
                    Text("No tasks found.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(filteredTasks) { task in
                    taskRow(task)
                }
            }
        }
        .navigationTitle("Async Tasks (\(totalCount))")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(Self.statusOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("asyncTaskStatusFilterMenu")
            }
            ToolbarItem {
                Button {
                    Task { await cleanupCompleted() }
                } label: {
                    Label("Clear Completed", systemImage: "trash")
                }
                .accessibilityIdentifier("cleanupCompletedTasksButton")
                .help("Clear Completed Tasks")
            }
        }
        .alert("Something went wrong", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: Binding(
            get: { downloadedFileURL.map { IdentifiableURL(url: $0) } },
            set: { downloadedFileURL = $0?.url }
        )) { wrapped in
            ShareLink(item: wrapped.url) {
                Label("Save or Share \(wrapped.url.lastPathComponent)", systemImage: "square.and.arrow.up")
            }
            .padding()
        }
        .task {
            await reload()
            await listenForLiveUpdates()
        }
    }

    @ViewBuilder
    private func taskRow(_ task: AsyncTaskDTO) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.taskType)
                    .fontWeight(.semibold)
                Spacer()
                statusBadge(task.status)
            }
            if let name = task.metadataTableName {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !task.isTerminal {
                ProgressView(value: task.progressPercentage, total: 100)
                if !task.progressDescription.isEmpty {
                    Text(task.progressDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if task.status == "FAILURE", !task.errorMessage.isEmpty {
                Text(task.errorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .accessibilityIdentifier("asyncTaskRow_\(task.id)")
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await cancelOrDelete(task) }
            } label: {
                Label(task.isTerminal ? "Delete" : "Cancel", systemImage: task.isTerminal ? "trash" : "xmark.circle")
            }
            if task.status == "SUCCESS" {
                Button {
                    Task { await download(task) }
                } label: {
                    if downloadingTaskID == task.id {
                        ProgressView()
                    } else {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                }
                .tint(.blue)
                .disabled(downloadingTaskID != nil)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                Task { await cancelOrDelete(task) }
            } label: {
                Label(task.isTerminal ? "Delete" : "Cancel", systemImage: task.isTerminal ? "trash" : "xmark.circle")
            }
            if task.status == "SUCCESS" {
                Button {
                    Task { await download(task) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: String) -> some View {
        Text(status.capitalized)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color(for: status).opacity(0.15))
            .foregroundStyle(color(for: status))
            .clipShape(Capsule())
    }

    private func color(for status: String) -> Color {
        switch status {
        case "SUCCESS": return .green
        case "FAILURE": return .red
        case "CANCELLED": return .secondary
        default: return .orange
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await appSession.makeSyncServices().asyncTaskSync.fetchAll(limit: 100)
            tasks = page.results
            totalCount = page.count
        } catch {
            tasks = []
        }
    }

    private func listenForLiveUpdates() async {
        for await event in await appSession.asyncTaskEvents() {
            guard let index = tasks.firstIndex(where: { $0.id == event.taskID }) else { continue }
            tasks[index] = AsyncTaskDTO(
                id: tasks[index].id,
                taskType: event.taskType ?? tasks[index].taskType,
                status: event.status,
                metadataTableID: tasks[index].metadataTableID,
                metadataTableName: tasks[index].metadataTableName,
                progressPercentage: event.progressPercentage ?? tasks[index].progressPercentage,
                progressDescription: event.progressDescription ?? tasks[index].progressDescription,
                createdAt: tasks[index].createdAt,
                startedAt: tasks[index].startedAt,
                completedAt: tasks[index].completedAt,
                duration: tasks[index].duration,
                errorMessage: event.errorMessage ?? tasks[index].errorMessage,
                traceback: tasks[index].traceback
            )
        }
    }

    private func cancelOrDelete(_ task: AsyncTaskDTO) async {
        do {
            try await appSession.makeSyncServices().asyncTaskSync.cancel(id: task.id)
            await reload()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func cleanupCompleted() async {
        do {
            try await appSession.makeSyncServices().asyncTaskSync.cleanupCompleted()
            await reload()
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }

    private func download(_ task: AsyncTaskDTO) async {
        downloadingTaskID = task.id
        defer { downloadingTaskID = nil }
        do {
            let (data, suggestedFilename) = try await appSession.makeSyncServices().asyncTaskSync.downloadFile(id: task.id)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(suggestedFilename ?? "\(task.id).dat")
            try data.write(to: url)
            downloadedFileURL = url
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
