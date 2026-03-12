import SwiftUI

// MARK: - ProjectsTabView (root of Projects tab)

struct ProjectsTabView: View {
    let session: UserSession
    let dependencies: AppDependencies

    @State private var projects: [UserProject] = []
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var showCreateProject = false
    @State private var newProjectName = ""
    @State private var isCreating = false
    @State private var createError: String?
    @State private var deleteError: String?
    @State private var projectToDelete: UserProject?
    @State private var showDeleteConfirm = false

    private var filteredProjects: [UserProject] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return projects }
        return projects.filter { project in
            project.name.localizedCaseInsensitiveContains(trimmed)
            || (project.goal?.localizedCaseInsensitiveContains(trimmed) == true)
            || (project.manualText?.localizedCaseInsensitiveContains(trimmed) == true)
        }
    }

    var body: some View {
        List {
            // Search bar
            Section {
                DSSearchBar(text: $searchText, placeholder: "Search projects…")
                    .listRowInsets(EdgeInsets())
            }
            .listRowBackground(DS.ColorToken.canvas)

            if isLoading && projects.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(DS.ColorToken.canvas)
            } else if projects.isEmpty {
                Section {
                    DSEmptyState(
                        icon: "folder.badge.plus",
                        title: "No projects yet",
                        message: "Tap + to create your first project. Each project holds its own knowledge base, files, and AI context."
                    )
                }
                .listRowBackground(DS.ColorToken.canvas)
            } else if filteredProjects.isEmpty {
                Section {
                    DSEmptyState(
                        icon: "magnifyingglass",
                        title: "No results",
                        message: "No projects match \"\(searchText.trimmingCharacters(in: .whitespaces))\"."
                    )
                }
                .listRowBackground(DS.ColorToken.canvas)
            } else {
                Section {
                    ForEach(filteredProjects) { project in
                        NavigationLink(destination: ProjectDetailView(
                            project: project,
                            session: session,
                            dependencies: dependencies,
                            onProjectUpdated: { loadProjects() }
                        )) {
                            ProjectRowView(project: project)
                        }
                        .listRowBackground(DS.ColorToken.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                projectToDelete = project
                                showDeleteConfirm = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    let count = filteredProjects.count
                    Text("\(count) project\(count == 1 ? "" : "s")\(searchText.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " found")")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                }
            }

            if let error = deleteError {
                Section {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.error)
                }
                .listRowBackground(DS.ColorToken.canvas)
            }
        }
        .scrollContentBackground(.hidden)
        .background(DS.ColorToken.canvas)
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newProjectName = ""
                    createError = nil
                    showCreateProject = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .task { loadProjects() }
        .refreshable { await refreshProjects() }
        .sheet(isPresented: $showCreateProject) {
            createProjectSheet
        }
        .confirmationDialog(
            "Delete \"\(projectToDelete?.name ?? "project")\"?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let p = projectToDelete { deleteProject(p) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the project and all its files, transcripts, and knowledge.")
        }
    }

    // MARK: - Create project sheet

    private var createProjectSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Spacing.x24) {
                VStack(alignment: .leading, spacing: DS.Spacing.x8) {
                    Text("Project Name")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.textSecondary)
                    TextField("e.g. Q3 Product Launch", text: $newProjectName)
                        .font(DS.Typography.body)
                        .padding(.horizontal, DS.Spacing.x12)
                        .padding(.vertical, DS.Spacing.x12)
                        .background(DS.ColorToken.elevated)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .stroke(DS.ColorToken.border, lineWidth: 1)
                        )
                        .onSubmit {
                            if !newProjectName.trimmingCharacters(in: .whitespaces).isEmpty {
                                createProject()
                            }
                        }
                }

                if let error = createError {
                    Text(error)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.ColorToken.error)
                }

                DSButton(
                    title: "Create Project",
                    icon: "folder.badge.plus",
                    kind: .primary,
                    isLoading: isCreating,
                    isDisabled: newProjectName.trimmingCharacters(in: .whitespaces).isEmpty
                ) {
                    createProject()
                }

                Spacer()
            }
            .padding(DS.Spacing.x24)
            .background(DS.ColorToken.canvas)
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { showCreateProject = false }
                }
            }
        }
    }

    // MARK: - Data

    private func loadProjects() {
        isLoading = true
        Task {
            if let loaded = try? await dependencies.projectRepository.listProjects(token: session.accessToken) {
                await MainActor.run {
                    projects = loaded.sorted { $0.updatedAtISO8601 > $1.updatedAtISO8601 }
                    isLoading = false
                }
            } else {
                await MainActor.run { isLoading = false }
            }
        }
    }

    private func refreshProjects() async {
        if let loaded = try? await dependencies.projectRepository.listProjects(token: session.accessToken) {
            projects = loaded.sorted { $0.updatedAtISO8601 > $1.updatedAtISO8601 }
        }
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreating = true
        createError = nil
        Task {
            do {
                let project = try await dependencies.projectRepository.createProject(name: name, token: session.accessToken)
                await MainActor.run {
                    projects.insert(project, at: 0)
                    isCreating = false
                    showCreateProject = false
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    createError = error.localizedDescription
                }
            }
        }
    }

    private func deleteProject(_ project: UserProject) {
        Task {
            do {
                try await dependencies.projectRepository.deleteProject(projectId: project.projectId, token: session.accessToken)
                await MainActor.run {
                    projects.removeAll { $0.projectId == project.projectId }
                    deleteError = nil
                }
            } catch {
                await MainActor.run { deleteError = error.localizedDescription }
            }
        }
    }
}

// MARK: - ProjectRowView

private struct ProjectRowView: View {
    let project: UserProject

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x4) {
            HStack(spacing: DS.Spacing.x12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.ColorToken.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(DS.Typography.bodyMedium)
                        .foregroundStyle(DS.ColorToken.textPrimary)
                        .lineLimit(1)
                    if let goal = project.goal, !goal.isEmpty {
                        Text(goal)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text(formattedDate(project.updatedAtISO8601))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.ColorToken.textTertiary)
            }
        }
        .padding(.vertical, DS.Spacing.x4)
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let rel = RelativeDateTimeFormatter()
        rel.unitsStyle = .abbreviated
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
