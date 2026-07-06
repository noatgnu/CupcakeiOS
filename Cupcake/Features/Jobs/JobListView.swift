import CupcakeModels
import SwiftData
import SwiftUI

struct JobListView: View {
    let ontologyStore: ModelContainer

    @Query(sort: \CachedInstrumentJob.jobName) private var jobs: [CachedInstrumentJob]
    @Query private var projects: [CachedProject]

    @State private var isShowingNewJobSheet = false

    private func projectName(for job: CachedInstrumentJob) -> String? {
        guard let projectClientID = job.projectClientID else { return nil }
        return projects.first(where: { $0.clientID == projectClientID })?.projectName
    }

    var body: some View {
        NavigationStack {
            Group {
                if jobs.isEmpty {
                    ContentUnavailableView(
                        "No Jobs",
                        systemImage: "list.clipboard",
                        description: Text("Create a job to submit instrument work for analysis.")
                    )
                } else {
                    List(jobs) { job in
                        NavigationLink(value: job.clientID) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.jobName ?? "Untitled Job")
                                HStack(spacing: 4) {
                                    Text(job.status.capitalized)
                                    if let projectName = projectName(for: job) {
                                        Text("· \(projectName)")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem {
                    NavigationLink {
                        ProjectListView()
                    } label: {
                        Label("Projects", systemImage: "folder")
                    }
                    .accessibilityIdentifier("projectsLink")
                }
                ToolbarItem {
                    Button {
                        isShowingNewJobSheet = true
                    } label: {
                        Label("New Job", systemImage: "plus")
                    }
                    .accessibilityIdentifier("newJobButton")
                }
            }
            .sheet(isPresented: $isShowingNewJobSheet) {
                NewJobSheet()
            }
            .navigationDestination(for: UUID.self) { jobClientID in
                JobDetailView(jobClientID: jobClientID, ontologyStore: ontologyStore)
            }
        }
    }
}
