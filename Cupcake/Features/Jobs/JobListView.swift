import CupcakeModels
import SwiftData
import SwiftUI

struct JobListView: View {
    let ontologyStore: ModelContainer

    @Query(sort: \CachedInstrumentJob.jobName) private var jobs: [CachedInstrumentJob]
    @Query private var projects: [CachedProject]

    @State private var isShowingNewJobSheet = false
    @State private var isShowingProjects = false
    @State private var selectedJobID: UUID?
    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "All Jobs")]
    @State private var searchText = ""
    @State private var statusFilter: JobStatusFilter = .all

    private enum JobStatusFilter: String, CaseIterable {
        case all = "All"
        case draft = "Draft"
        case submitted = "Submitted"
        case inProgress = "In Progress"
        case completed = "Completed"
        case cancelled = "Cancelled"

        var rawStatus: String? {
            switch self {
            case .all: nil
            case .draft: "draft"
            case .submitted: "submitted"
            case .inProgress: "in_progress"
            case .completed: "completed"
            case .cancelled: "cancelled"
            }
        }
    }

    private var filteredJobs: [CachedInstrumentJob] {
        jobs
            .filter { statusFilter.rawStatus == nil || $0.status == statusFilter.rawStatus }
            .filter { searchText.isEmpty || $0.jobName?.localizedCaseInsensitiveContains(searchText) == true }
    }

    private func projectName(for job: CachedInstrumentJob) -> String? {
        guard let projectClientID = job.projectClientID else { return nil }
        return projects.first(where: { $0.clientID == projectClientID })?.projectName
    }

    var body: some View {
        TwoPanelExplorerView(pathStack: $pathStack, pushesDetailOnCompact: true) {
            SelectableExplorerList(
                selection: $selectedJobID,
                isEmpty: filteredJobs.isEmpty,
                emptyTitle: "No Jobs",
                emptySystemImage: "list.clipboard",
                emptyMessage: jobs.isEmpty ? "Create a job to submit instrument work for analysis." : "No jobs match your search/filter."
            ) {
                ForEach(filteredJobs) { job in
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
                    .tag(job.clientID)
                }
            }
            .navigationTitle("Jobs")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingProjects = true
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
            .sheet(isPresented: $isShowingProjects) {
                NavigationStack {
                    ProjectListView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingProjects = false }
                            }
                        }
                }
                .frame(minWidth: 360, minHeight: 500)
            }
        } detail: {
            if let selectedJobID {
                JobDetailView(jobClientID: selectedJobID, ontologyStore: ontologyStore)
            } else {
                ExplorerList(
                    isEmpty: true,
                    emptyTitle: "No Job Selected",
                    emptySystemImage: "list.clipboard",
                    emptyMessage: "Select a job to see its details."
                ) { EmptyView() }
            }
        } sidebarHeader: {
            VStack(spacing: 8) {
                TextField("Search jobs", text: $searchText)
                    .accessibilityIdentifier("jobSearchField")
                HStack {
                    Text("Status")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("Status", selection: $statusFilter) {
                        ForEach(JobStatusFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityIdentifier("jobStatusFilterPicker")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .onChange(of: selectedJobID) { _, newValue in
            guard let newValue, let job = jobs.first(where: { $0.clientID == newValue }) else {
                pathStack = [pathStack[0]]
                return
            }
            pathStack = [pathStack[0], BreadcrumbSegment(id: nil, name: job.jobName ?? "Untitled Job")]
        }
        .onChange(of: pathStack) { _, newValue in
            if newValue.count == 1 {
                selectedJobID = nil
            }
        }
    }
}
