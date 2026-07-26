import CupcakeModels
import SwiftData
import SwiftUI

struct JobListView: View {
    let ontologyStore: ModelContainer

    @Environment(AppSession.self) private var appSession
    @Environment(\.openWindow) private var openWindow
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \CachedInstrumentJob.createdAt, order: .reverse) private var jobs: [CachedInstrumentJob]
    @Query private var projects: [CachedProject]
    @Query private var labGroups: [CachedLabGroup]

    @State private var isShowingNewJobSheet = false
    @State private var isShowingProjects = false
    @State private var isShowingTableTemplateManagement = false
    @State private var isShowingColumnTemplateManagement = false
    @State private var isShowingMetadataTablesBrowser = false
    @State private var isShowingLabGroups = false
    @State private var selectedJobID: UUID?
    @State private var pathStack: [BreadcrumbSegment] = [BreadcrumbSegment(id: nil, name: "All Jobs")]
    @State private var searchText = ""
    @State private var statusFilter: JobStatusFilter = .all
    @State private var modeFilter: JobModeFilter = .personal

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

    private enum JobModeFilter: String, CaseIterable {
        case personal = "Personal"
        case assigned = "Assigned"
    }

    private var myLabGroupServerIDs: Set<Int64> {
        Set(labGroups.compactMap(\.serverID))
    }

    private func matchesMode(_ job: CachedInstrumentJob) -> Bool {
        switch modeFilter {
        case .personal:
            return job.ownerServerID == nil || job.ownerServerID == appSession.currentUserID
        case .assigned:
            let isStaffAssigned = appSession.currentUserID.map { job.staffServerIDs.contains($0) } ?? false
            let isInMyLabGroup = job.labGroupServerID.map { myLabGroupServerIDs.contains($0) } ?? false
            let isLabGroupSubmitted = isInMyLabGroup && (job.status != "draft")
            return isStaffAssigned || isLabGroupSubmitted
        }
    }

    private var filteredJobs: [CachedInstrumentJob] {
        jobs
            .filter(matchesMode)
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
                        if PlatformWindowPreference.prefersSeparateWindow {
                            PlatformWindowPreference.openOrFocusWindow(id: "table-template-manager", using: openWindow)
                        } else {
                            isShowingTableTemplateManagement = true
                        }
                    } label: {
                        Label("Table Templates", systemImage: "folder.badge.gearshape")
                    }
                    .accessibilityIdentifier("manageMetadataTableTemplatesButton")
                }
                ToolbarItem {
                    Button {
                        if PlatformWindowPreference.prefersSeparateWindow {
                            PlatformWindowPreference.openOrFocusWindow(id: "column-template-manager", using: openWindow)
                        } else {
                            isShowingColumnTemplateManagement = true
                        }
                    } label: {
                        Label("Column Templates", systemImage: "square.stack.3d.up")
                    }
                    .accessibilityIdentifier("manageColumnTemplatesButton")
                }
                ToolbarItem {
                    Button {
                        if PlatformWindowPreference.prefersSeparateWindow {
                            PlatformWindowPreference.openOrFocusWindow(id: "metadata-tables-browser", using: openWindow)
                        } else {
                            isShowingMetadataTablesBrowser = true
                        }
                    } label: {
                        Label("Metadata Tables", systemImage: "tablecells")
                    }
                    .accessibilityIdentifier("metadataTablesBrowserButton")
                }
                ToolbarItem {
                    Button {
                        if PlatformWindowPreference.prefersSeparateWindow {
                            PlatformWindowPreference.openOrFocusWindow(id: "lab-group-manager", using: openWindow)
                        } else {
                            isShowingLabGroups = true
                        }
                    } label: {
                        Label("Lab Groups", systemImage: "person.3")
                    }
                    .accessibilityIdentifier("labGroupsButton")
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
            .sheet(isPresented: $isShowingTableTemplateManagement) {
                NavigationStack {
                    TableTemplateManagementView(ontologyStore: ontologyStore)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingTableTemplateManagement = false }
                                    .accessibilityIdentifier("doneButton")
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingColumnTemplateManagement) {
                NavigationStack {
                    ColumnTemplateManagementSheet()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingColumnTemplateManagement = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingMetadataTablesBrowser) {
                NavigationStack {
                    MetadataTablesBrowserView(ontologyStore: ontologyStore)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingMetadataTablesBrowser = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $isShowingLabGroups) {
                NavigationStack {
                    LabGroupListView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { isShowingLabGroups = false }
                            }
                        }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .newJobRequested)) { _ in
                isShowingNewJobSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .newProjectRequested)) { _ in
                isShowingProjects = true
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
                Picker("Mode", selection: $modeFilter) {
                    ForEach(JobModeFilter.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("jobModeFilterPicker")
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
            appSession.isShowingPushedDetail = newValue.count > 1 && horizontalSizeClass == .compact
        }
        .onAppear {
            appSession.isShowingPushedDetail = pathStack.count > 1 && horizontalSizeClass == .compact
        }
    }
}
