import Foundation

struct UserContextService: ProjectRepository {
    private let api = APIClient()

    func listProjects(token: String) async throws -> [UserProject] {
        let data = try await api.request(path: "/projects", token: token)
        return try JSONDecoder().decode([UserProject].self, from: data)
    }

    func createProject(name: String, token: String) async throws -> UserProject {
        let payload = ["name": name]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/projects", method: "POST", token: token, body: body)
        return try JSONDecoder().decode(UserProject.self, from: data)
    }

    func uploadTextSource(projectId: String, title: String, text: String, token: String) async throws -> SourceItem {
        let payload = ["title": title, "text": text]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/projects/\(projectId)/sources/text", method: "POST", token: token, body: body)
        return try JSONDecoder().decode(SourceItem.self, from: data)
    }

    /// Save a meeting transcript to the project knowledge base.
    /// Uses a lightweight backend endpoint (cheaper + faster than full text analysis).
    func saveTranscript(projectId: String, title: String, transcript: String, token: String) async throws -> SourceItem {
        let payload = ["title": title, "transcript": transcript]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(
            path: "/projects/\(projectId)/sources/transcript",
            method: "POST",
            token: token,
            body: body
        )
        return try JSONDecoder().decode(SourceItem.self, from: data)
    }

    func uploadFileSource(projectId: String, fileName: String, mimeType: String, fileData: Data, token: String) async throws -> SourceItem {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = api.multipartBody(fieldName: "file", fileName: fileName, mimeType: mimeType, data: fileData, boundary: boundary)

        let data = try await api.request(
            path: "/projects/\(projectId)/sources/file",
            method: "POST",
            token: token,
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
        return try JSONDecoder().decode(SourceItem.self, from: data)
    }

    func fetchProjectContext(projectId: String, token: String) async throws -> ProjectContextSummary {
        let data = try await api.request(path: "/projects/\(projectId)/context", token: token)
        return try JSONDecoder().decode(ProjectContextSummary.self, from: data)
    }
}

actor InMemoryProjectRepository: ProjectRepository {
    private var projects: [UserProject]
    private var sourcesByProjectId: [String: [SourceItem]]
    private var sourceTextsByProjectId: [String: [String]]

    init(
        projects: [UserProject] = [],
        sourcesByProjectId: [String: [SourceItem]] = [:],
        sourceTextsByProjectId: [String: [String]] = [:]
    ) {
        self.projects = projects
        self.sourcesByProjectId = sourcesByProjectId
        self.sourceTextsByProjectId = sourceTextsByProjectId
    }

    init(launchConfiguration: AppLaunchConfiguration) {
        let now = ISO8601DateFormatter().string(from: Date())
        let projectId = "project-1"
        let project = UserProject(projectId: projectId, name: launchConfiguration.preloadProjectName ?? "Sample Project", createdAtISO8601: now, updatedAtISO8601: now)
        let baseSource = SourceItem(
            sourceId: "source-1",
            sourceType: "text",
            title: "Project Context",
            analysis: launchConfiguration.preloadProjectContext ?? "",
            createdAtISO8601: now
        )
        self.projects = launchConfiguration.preloadProjectName == nil ? [] : [project]
        self.sourcesByProjectId = launchConfiguration.preloadProjectName == nil ? [:] : [projectId: [baseSource]]
        self.sourceTextsByProjectId = launchConfiguration.preloadProjectName == nil ? [:] : [projectId: [launchConfiguration.preloadProjectContext ?? ""]]
    }

    func listProjects(token: String) async throws -> [UserProject] {
        projects
    }

    func createProject(name: String, token: String) async throws -> UserProject {
        let now = ISO8601DateFormatter().string(from: Date())
        let project = UserProject(projectId: UUID().uuidString, name: name, createdAtISO8601: now, updatedAtISO8601: now)
        projects.insert(project, at: 0)
        return project
    }

    func uploadTextSource(projectId: String, title: String, text: String, token: String) async throws -> SourceItem {
        let source = makeSource(title: title, type: "text", text: text)
        append(source: source, rawText: text, projectId: projectId)
        return source
    }

    func uploadFileSource(projectId: String, fileName: String, mimeType: String, fileData: Data, token: String) async throws -> SourceItem {
        let text = String(decoding: fileData, as: UTF8.self)
        let source = makeSource(title: fileName, type: "file", text: text)
        append(source: source, rawText: text, projectId: projectId)
        return source
    }

    func saveTranscript(projectId: String, title: String, transcript: String, token: String) async throws -> SourceItem {
        let source = makeSource(title: title, type: "transcript", text: transcript)
        append(source: source, rawText: transcript, projectId: projectId)
        return source
    }

    func fetchProjectContext(projectId: String, token: String) async throws -> ProjectContextSummary {
        let projectName = projects.first(where: { $0.projectId == projectId })?.name ?? "Project"
        let texts = sourceTextsByProjectId[projectId] ?? []
        let summary = ([projectName] + texts).filter { !$0.isEmpty }.joined(separator: "\n")
        return ProjectContextSummary(
            summary: summary.isEmpty ? "No saved context yet" : summary,
            sources: sourcesByProjectId[projectId] ?? [],
            lastUpdatedISO8601: ISO8601DateFormatter().string(from: Date())
        )
    }

    func storedSourceTexts(projectId: String) -> [String] {
        sourceTextsByProjectId[projectId] ?? []
    }

    private func makeSource(title: String, type: String, text: String) -> SourceItem {
        SourceItem(
            sourceId: UUID().uuidString,
            sourceType: type,
            title: title,
            analysis: text,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func append(source: SourceItem, rawText: String, projectId: String) {
        sourcesByProjectId[projectId, default: []].append(source)
        sourceTextsByProjectId[projectId, default: []].append(rawText)
    }
}
