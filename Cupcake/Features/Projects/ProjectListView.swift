import CupcakeModels
import SwiftData
import SwiftUI

/// Matches the reference web app's standalone Projects page (`home/projects.ts`) — its own
/// list + create action, reachable independently of job creation.
struct ProjectListView: View {
    @Query(sort: \CachedProject.projectName) private var projects: [CachedProject]
    @State private var isShowingNewProjectSheet = false

    var body: some View {
        Group {
            if projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "folder",
                    description: Text("Create a project to organize jobs and sessions.")
                )
            } else {
                List(projects) { project in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.projectName)
                        if let description = project.projectDescription, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
    }
}
