import CupcakeModels
import CupcakeNetworking
import CupcakeSync
import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Environment(AppSession.self) private var appSession
    @Query(sort: \CachedProject.createdAt, order: .reverse) private var projects: [CachedProject]
    @State private var isShowingNewProjectSheet = false
    @State private var isShowingEditProjectSheet = false
    @State private var selectedProjectID: UUID?
    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "All Projects")]
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            SelectableExplorerList(
                selection: $selectedProjectID,
                isEmpty: projects.isEmpty,
                emptyTitle: "No Projects",
                emptySystemImage: "folder",
                emptyMessage: "Create a project to organize jobs and sessions."
            ) {
                ForEach(projects) { project in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.projectName)
                        if let description = project.projectDescription, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(project.clientID)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingNewProjectSheet = true
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newProjectButton")
                }
            }
            .sheet(isPresented: $isShowingNewProjectSheet) {
                NewProjectSheet()
            }
        } detail: {
            if let selectedProjectID, let project = projects.first(where: { $0.clientID == selectedProjectID }) {
                List {
                    Section("Name") {
                        Text(project.projectName)
                    }
                    if let description = project.projectDescription, !description.isEmpty {
                        Section("Description") {
                            Text(description)
                        }
                    }
                    Section {
                        Button("Delete Project", role: .destructive) {
                            Task { await delete(project) }
                        }
                        .disabled(project.serverID == nil)
                        .accessibilityIdentifier("deleteProjectButton")
                    }
                }
                .navigationTitle(project.projectName)
                .toolbar {
                    ToolbarItem {
                        Button {
                            isShowingEditProjectSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .disabled(project.serverID == nil)
                        .accessibilityIdentifier("editProjectButton")
                    }
                }
                .sheet(isPresented: $isShowingEditProjectSheet) {
                    NewProjectSheet(existingProject: project)
                }
            } else {
                ExplorerList(
                    isEmpty: true,
                    emptyTitle: "No Project Selected",
                    emptySystemImage: "folder",
                    emptyMessage: "Select a project to see its details."
                ) { EmptyView() }
            }
        }
        .onChange(of: selectedProjectID) { _, newValue in
            guard let newValue, let project = projects.first(where: { $0.clientID == newValue }) else {
                pathStack = [pathStack[0]]
                return
            }
            pathStack = [pathStack[0], BreadcrumbSegment(id: nil, name: project.projectName)]
        }
        .onChange(of: pathStack) { _, newValue in
            if newValue.count == 1 {
                selectedProjectID = nil
            }
        }
        .alert("Couldn't delete project", isPresented: $isShowingError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func delete(_ project: CachedProject) async {
        guard let serverID = project.serverID else { return }
        do {
            try await appSession.makeSyncServices().projectSync.delete(serverID: serverID)
            selectedProjectID = nil
        } catch {
            errorMessage = error.userFacingMessage
            isShowingError = true
        }
    }
}
