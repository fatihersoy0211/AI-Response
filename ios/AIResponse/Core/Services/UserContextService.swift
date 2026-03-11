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

    func fetchProjectContextSnapshot(projectId: String, token: String) async throws -> ProjectContextSnapshot {
        let data = try await api.request(path: "/projects/\(projectId)/context/snapshot", token: token)
        return try JSONDecoder().decode(ProjectContextSnapshot.self, from: data)
    }

    func saveAudioAsset(projectId: String, title: String, mimeType: String, token: String) async throws -> ProjectAudioAsset {
        let payload = ["title": title, "mimeType": mimeType]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/projects/\(projectId)/audio_assets", method: "POST", token: token, body: body)
        return try JSONDecoder().decode(ProjectAudioAsset.self, from: data)
    }

    func saveProjectSummary(projectId: String, style: String, content: String, token: String) async throws -> ProjectSummary {
        let payload = ["style": style, "content": content]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(path: "/projects/\(projectId)/summaries", method: "POST", token: token, body: body)
        return try JSONDecoder().decode(ProjectSummary.self, from: data)
    }

    func listProjectSummaries(projectId: String, token: String) async throws -> [ProjectSummary] {
        let data = try await api.request(path: "/projects/\(projectId)/summaries", token: token)
        return try JSONDecoder().decode([ProjectSummary].self, from: data)
    }
}

actor InMemoryProjectRepository: ProjectRepository {
    private var projects: [UserProject]
    private var documentsByProjectId: [String: [SourceItem]]
    private var transcriptsByProjectId: [String: [SourceItem]]
    private var audioAssetsByProjectId: [String: [ProjectAudioAsset]]
    private var summariesByProjectId: [String: [ProjectSummary]]
    private var sourceTextsByProjectId: [String: [String]]

    init(
        projects: [UserProject] = [],
        sourcesByProjectId: [String: [SourceItem]] = [:],
        sourceTextsByProjectId: [String: [String]] = [:]
    ) {
        self.projects = projects
        self.documentsByProjectId = sourcesByProjectId
        self.transcriptsByProjectId = [:]
        self.audioAssetsByProjectId = [:]
        self.summariesByProjectId = [:]
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
        self.documentsByProjectId = launchConfiguration.preloadProjectName == nil ? [:] : [projectId: [baseSource]]
        self.transcriptsByProjectId = [:]
        self.audioAssetsByProjectId = [:]
        self.summariesByProjectId = [:]
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
        documentsByProjectId[projectId, default: []].append(source)
        sourceTextsByProjectId[projectId, default: []].append(text)
        return source
    }

    func uploadFileSource(projectId: String, fileName: String, mimeType: String, fileData: Data, token: String) async throws -> SourceItem {
        let text = String(decoding: fileData, as: UTF8.self)
        let source = makeSource(title: fileName, type: "file", text: text)
        documentsByProjectId[projectId, default: []].append(source)
        sourceTextsByProjectId[projectId, default: []].append(text)
        return source
    }

    func saveTranscript(projectId: String, title: String, transcript: String, token: String) async throws -> SourceItem {
        let source = makeSource(title: title, type: "transcript", text: transcript)
        transcriptsByProjectId[projectId, default: []].append(source)
        sourceTextsByProjectId[projectId, default: []].append(transcript)
        return source
    }

    func fetchProjectContext(projectId: String, token: String) async throws -> ProjectContextSummary {
        let projectName = projects.first(where: { $0.projectId == projectId })?.name ?? "Project"
        let texts = sourceTextsByProjectId[projectId] ?? []
        let summary = ([projectName] + texts).filter { !$0.isEmpty }.joined(separator: "\n")
        let docs = documentsByProjectId[projectId] ?? []
        let transcripts = transcriptsByProjectId[projectId] ?? []
        return ProjectContextSummary(
            summary: summary.isEmpty ? "No saved context yet" : summary,
            sources: docs + transcripts,
            lastUpdatedISO8601: ISO8601DateFormatter().string(from: Date())
        )
    }

    func fetchProjectContextSnapshot(projectId: String, token: String) async throws -> ProjectContextSnapshot {
        let projectName = projects.first(where: { $0.projectId == projectId })?.name ?? "Project"
        let docs = documentsByProjectId[projectId] ?? []
        let transcripts = transcriptsByProjectId[projectId] ?? []

        // Layer 2: join document analyses
        let documentContext = docs
            .map { "Document: \($0.title)\n\($0.analysis)" }
            .joined(separator: "\n\n")

        // Layer 3: join transcript analyses
        let transcriptHistory = transcripts
            .map { "Transcript: \($0.title)\n\($0.analysis)" }
            .joined(separator: "\n\n")

        return ProjectContextSnapshot(
            projectName: projectName,
            documentContext: documentContext,
            transcriptHistory: transcriptHistory,
            documents: docs,
            transcripts: transcripts,
            lastUpdatedISO8601: ISO8601DateFormatter().string(from: Date())
        )
    }

    func saveAudioAsset(projectId: String, title: String, mimeType: String, token: String) async throws -> ProjectAudioAsset {
        let asset = ProjectAudioAsset(
            assetId: UUID().uuidString,
            title: title,
            mimeType: mimeType,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
        audioAssetsByProjectId[projectId, default: []].append(asset)
        return asset
    }

    func saveProjectSummary(projectId: String, style: String, content: String, token: String) async throws -> ProjectSummary {
        let summary = ProjectSummary(
            summaryId: UUID().uuidString,
            style: style,
            content: content,
            generatedAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
        summariesByProjectId[projectId, default: []].append(summary)
        return summary
    }

    func listProjectSummaries(projectId: String, token: String) async throws -> [ProjectSummary] {
        summariesByProjectId[projectId] ?? []
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
}
