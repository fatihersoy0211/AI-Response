import Foundation

struct UserContextService: ProjectRepository {
    private let api = APIClient()
    private static let localStore = ProjectScopedLocalStore()

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
        let source = try JSONDecoder().decode(SourceItem.self, from: data)
        await Self.localStore.recordDocument(
            projectId: projectId,
            fileName: title,
            fileType: "text/plain",
            storedPath: nil,
            extractedText: text,
            source: source
        )
        return source
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
        let source = try JSONDecoder().decode(SourceItem.self, from: data)
        let extractedText = String(data: fileData, encoding: .utf8) ?? ""
        await Self.localStore.recordDocument(
            projectId: projectId,
            fileName: fileName,
            fileType: mimeType,
            storedPath: nil,
            extractedText: extractedText,
            source: source
        )
        return source
    }

    func saveTranscript(projectId: String, title: String, transcript: String, token: String) async throws -> SourceItem {
        let payload = ["title": title, "transcript": transcript]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await api.request(
            path: "/projects/\(projectId)/sources/transcript",
            method: "POST",
            token: token,
            body: body
        )
        let source = try JSONDecoder().decode(SourceItem.self, from: data)
        await Self.localStore.recordTranscript(
            projectId: projectId,
            title: title,
            transcript: transcript,
            source: source,
            sessionId: nil,
            audioAssetId: nil,
            sourceType: "liveListening",
            isFinal: true
        )
        return source
    }

    func fetchProjectContext(projectId: String, token: String) async throws -> ProjectContextSummary {
        let snapshot = try await fetchProjectContextSnapshot(projectId: projectId, token: token)
        return ProjectContextSummary(
            summary: snapshot.mergedText.isEmpty ? "No saved context yet" : snapshot.mergedText,
            sources: snapshot.allSources,
            lastUpdatedISO8601: snapshot.lastUpdatedISO8601
        )
    }

    func fetchProjectContextSnapshot(projectId: String, token: String) async throws -> ProjectContextSnapshot {
        let remote = try? await fetchRemoteSnapshot(projectId: projectId, token: token)
        return await Self.localStore.mergeSnapshot(
            projectId: projectId,
            remote: remote
        )
    }

    func saveAudioAsset(projectId: String, title: String, mimeType: String, token: String) async throws -> ProjectAudioAsset {
        let payload = ["title": title, "mimeType": mimeType]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let remoteAsset: ProjectAudioAsset?
        do {
            let data = try await api.request(path: "/projects/\(projectId)/audio_assets", method: "POST", token: token, body: body)
            remoteAsset = try JSONDecoder().decode(ProjectAudioAsset.self, from: data)
        } catch {
            remoteAsset = nil
        }

        let asset = remoteAsset ?? ProjectAudioAsset(
            assetId: UUID().uuidString,
            projectId: projectId,
            title: title,
            sourceType: "liveRecording",
            mimeType: mimeType,
            storedPath: nil,
            durationSeconds: nil,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date()),
            transcriptionStatus: "pending"
        )
        await Self.localStore.recordAudioAsset(asset)
        return asset
    }

    func saveProjectSummary(projectId: String, style: String, content: String, token: String) async throws -> ProjectSummary {
        let payload = ["style": style, "content": content]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let remoteSummary: ProjectSummary?
        do {
            let data = try await api.request(path: "/projects/\(projectId)/summaries", method: "POST", token: token, body: body)
            remoteSummary = try JSONDecoder().decode(ProjectSummary.self, from: data)
        } catch {
            remoteSummary = nil
        }

        let summary = remoteSummary ?? ProjectSummary(
            summaryId: UUID().uuidString,
            projectId: projectId,
            style: style,
            content: content,
            sourceSnapshotHash: nil,
            generatedAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
        await Self.localStore.recordSummary(summary)
        return summary
    }

    func listProjectSummaries(projectId: String, token: String) async throws -> [ProjectSummary] {
        await Self.localStore.listSummaries(projectId: projectId)
    }

    func listProjectDocuments(projectId: String, token: String) async throws -> [ProjectDocument] {
        await Self.localStore.listDocuments(projectId: projectId)
    }

    func listProjectAudioAssets(projectId: String, token: String) async throws -> [ProjectAudioAsset] {
        await Self.localStore.listAudioAssets(projectId: projectId)
    }

    func listProjectTranscripts(projectId: String, token: String) async throws -> [TranscriptSegment] {
        await Self.localStore.listTranscripts(projectId: projectId)
    }

    func importAudioAsset(
        projectId: String,
        fileName: String,
        mimeType: String,
        localFileURL: URL?,
        durationSeconds: TimeInterval?,
        sourceType: String,
        transcript: String?,
        token: String
    ) async throws -> ProjectAudioAsset {
        let asset = ProjectAudioAsset(
            assetId: UUID().uuidString,
            projectId: projectId,
            title: fileName,
            sourceType: sourceType,
            mimeType: mimeType,
            storedPath: localFileURL?.path,
            durationSeconds: durationSeconds,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date()),
            transcriptionStatus: transcript?.isEmpty == false ? "completed" : "failed"
        )
        await Self.localStore.recordAudioAsset(asset)

        if let transcript, !transcript.isEmpty {
            let transcriptTitle = "Transcript – \(fileName)"
            // 1. Push transcript to backend so it's available in server-side context
            let backendSource: SourceItem? = try? await {
                let payload = ["title": transcriptTitle, "transcript": transcript]
                let body = try JSONSerialization.data(withJSONObject: payload)
                let data = try await api.request(
                    path: "/projects/\(projectId)/sources/transcript",
                    method: "POST",
                    token: token,
                    body: body
                )
                return try JSONDecoder().decode(SourceItem.self, from: data)
            }()

            // 2. Persist locally (use backend source id if available for deduplication)
            let source = backendSource ?? SourceItem(
                sourceId: UUID().uuidString,
                sourceType: "transcript",
                title: transcriptTitle,
                analysis: transcript,
                createdAtISO8601: ISO8601DateFormatter().string(from: Date())
            )
            await Self.localStore.recordTranscript(
                projectId: projectId,
                title: source.title,
                transcript: transcript,
                source: source,
                sessionId: nil,
                audioAssetId: asset.assetId,
                sourceType: sourceType,   // preserves "uploadedAudio" vs "liveRecording"
                isFinal: true
            )
        }
        return asset
    }

    func saveChatTurn(projectId: String, role: String, content: String, token: String) async throws -> ChatTurn {
        await Self.localStore.appendChatTurn(projectId: projectId, role: role, content: content)
    }

    func listChatTurns(projectId: String, token: String) async throws -> [ChatTurn] {
        await Self.localStore.listChatTurns(projectId: projectId)
    }

    func clearChatTurns(projectId: String, token: String) async throws {
        await Self.localStore.clearChatTurns(projectId: projectId)
    }

    func buildAIGenerationContext(projectId: String, userName: String?, token: String) async throws -> AIGenerationContext {
        let snapshot = try await fetchProjectContextSnapshot(projectId: projectId, token: token)
        let transcripts = await Self.localStore.listTranscripts(projectId: projectId)
            .sorted { $0.createdAtISO8601 < $1.createdAtISO8601 }
        let latestTranscript = transcripts.last?.analysis ?? ""
        let olderTranscripts = transcripts.dropLast().map { "[\($0.title)] \($0.analysis)" }

        let manualText = await Self.localStore.loadNotes(projectId: projectId)
        let effectiveManualText = manualText.isEmpty ? snapshot.manualText : manualText

        let baseContext = [
            "Project: \(snapshot.projectName)",
            effectiveManualText.isEmpty ? nil : "Project Background:\n\(effectiveManualText)",
            snapshot.documentContext.isEmpty ? nil : snapshot.documentContext,
            snapshot.chatHistory.isEmpty ? nil : snapshot.chatHistory
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")

        if latestTranscript.isEmpty {
            return AIGenerationContext(
                projectId: projectId,
                projectName: snapshot.projectName,
                transcriptHistory: baseContext.isEmpty ? [] : [baseContext],
                liveTranscript: baseContext,
                userName: userName
            )
        }

        return AIGenerationContext(
            projectId: projectId,
            projectName: snapshot.projectName,
            transcriptHistory: ([baseContext] + olderTranscripts).filter { !$0.isEmpty },
            liveTranscript: latestTranscript,
            userName: userName
        )
    }

    func saveProjectNotes(projectId: String, text: String, token: String) async throws -> UserProject {
        let payload = ["manualText": text]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try? await api.request(
            path: "/projects/\(projectId)/notes",
            method: "PATCH",
            token: token,
            body: body
        )
        await Self.localStore.saveNotes(projectId: projectId, text: text)
        if let data, let project = try? JSONDecoder().decode(UserProject.self, from: data) {
            return project
        }
        // fallback local-only
        return UserProject(projectId: projectId, name: "", goal: nil, manualText: text, createdAtISO8601: "", updatedAtISO8601: "")
    }

    func loadProjectNotes(projectId: String, token: String) async throws -> String {
        await Self.localStore.loadNotes(projectId: projectId)
    }

    func deleteProjectSource(projectId: String, sourceId: String, token: String) async throws {
        _ = try await api.request(path: "/projects/\(projectId)/sources/\(sourceId)", method: "DELETE", token: token)
    }

    func deleteProject(projectId: String, token: String) async throws {
        _ = try await api.request(path: "/projects/\(projectId)", method: "DELETE", token: token)
    }

    private func fetchRemoteSnapshot(projectId: String, token: String) async throws -> ProjectContextSnapshot {
        let data = try await api.request(path: "/projects/\(projectId)/context/snapshot", token: token)
        return try JSONDecoder().decode(ProjectContextSnapshot.self, from: data)
    }
}

actor InMemoryProjectRepository: ProjectRepository {
    private var projects: [UserProject]
    private var documentsByProjectId: [String: [ProjectDocument]]
    private var transcriptsByProjectId: [String: [TranscriptSegment]]
    private var audioAssetsByProjectId: [String: [ProjectAudioAsset]]
    private var summariesByProjectId: [String: [ProjectSummary]]
    private var chatTurnsByProjectId: [String: [ChatTurn]]
    private var sourceItemsByProjectId: [String: [SourceItem]]
    private var notesByProjectId: [String: String] = [:]

    init(
        projects: [UserProject] = [],
        sourcesByProjectId: [String: [SourceItem]] = [:],
        sourceTextsByProjectId: [String: [String]] = [:]
    ) {
        self.projects = projects
        self.documentsByProjectId = [:]
        self.transcriptsByProjectId = [:]
        self.audioAssetsByProjectId = [:]
        self.summariesByProjectId = [:]
        self.chatTurnsByProjectId = [:]
        self.sourceItemsByProjectId = sourcesByProjectId

        for (projectId, texts) in sourceTextsByProjectId {
            for (index, text) in texts.enumerated() {
                let now = ISO8601DateFormatter().string(from: Date())
                documentsByProjectId[projectId, default: []].append(
                    ProjectDocument(
                        sourceId: UUID().uuidString,
                        projectId: projectId,
                        fileName: "Context \(index + 1)",
                        fileType: "text/plain",
                        storedPath: nil,
                        extractedText: text,
                        extractionStatus: "completed",
                        createdAtISO8601: now,
                        updatedAtISO8601: now
                    )
                )
            }
        }
    }

    init(launchConfiguration: AppLaunchConfiguration) {
        let now = ISO8601DateFormatter().string(from: Date())
        let projectId = "project-1"
        let project = UserProject(
            projectId: projectId,
            name: launchConfiguration.preloadProjectName ?? "Sample Project",
            goal: nil,
            manualText: nil,
            createdAtISO8601: now,
            updatedAtISO8601: now
        )
        self.projects = launchConfiguration.preloadProjectName == nil ? [] : [project]
        self.documentsByProjectId = [:]
        self.transcriptsByProjectId = [:]
        self.audioAssetsByProjectId = [:]
        self.summariesByProjectId = [:]
        self.chatTurnsByProjectId = [:]
        self.sourceItemsByProjectId = [:]

        if let projectName = launchConfiguration.preloadProjectName {
            let source = SourceItem(
                sourceId: "source-1",
                sourceType: "text",
                title: projectName,
                analysis: launchConfiguration.preloadProjectContext ?? "",
                createdAtISO8601: now
            )
            sourceItemsByProjectId[projectId] = [source]
            documentsByProjectId[projectId] = [
                ProjectDocument(
                    sourceId: source.sourceId,
                    projectId: projectId,
                    fileName: source.title,
                    fileType: "text/plain",
                    storedPath: nil,
                    extractedText: source.analysis,
                    extractionStatus: "completed",
                    createdAtISO8601: now,
                    updatedAtISO8601: now
                )
            ]
        }
    }

    func listProjects(token: String) async throws -> [UserProject] {
        projects
    }

    func createProject(name: String, token: String) async throws -> UserProject {
        let now = ISO8601DateFormatter().string(from: Date())
        let project = UserProject(projectId: UUID().uuidString, name: name, goal: nil, manualText: nil, createdAtISO8601: now, updatedAtISO8601: now)
        projects.insert(project, at: 0)
        return project
    }

    func uploadTextSource(projectId: String, title: String, text: String, token: String) async throws -> SourceItem {
        let source = makeSource(projectId: projectId, title: title, type: "text", text: text)
        documentsByProjectId[projectId, default: []].append(
            ProjectDocument(
                sourceId: source.sourceId,
                projectId: projectId,
                fileName: title,
                fileType: "text/plain",
                storedPath: nil,
                extractedText: text,
                extractionStatus: "completed",
                createdAtISO8601: source.createdAtISO8601,
                updatedAtISO8601: source.createdAtISO8601
            )
        )
        return source
    }

    func uploadFileSource(projectId: String, fileName: String, mimeType: String, fileData: Data, token: String) async throws -> SourceItem {
        let text = String(decoding: fileData, as: UTF8.self)
        let source = makeSource(projectId: projectId, title: fileName, type: "file", text: text)
        documentsByProjectId[projectId, default: []].append(
            ProjectDocument(
                sourceId: source.sourceId,
                projectId: projectId,
                fileName: fileName,
                fileType: mimeType,
                storedPath: nil,
                extractedText: text,
                extractionStatus: "completed",
                createdAtISO8601: source.createdAtISO8601,
                updatedAtISO8601: source.createdAtISO8601
            )
        )
        return source
    }

    func saveTranscript(projectId: String, title: String, transcript: String, token: String) async throws -> SourceItem {
        let source = makeSource(projectId: projectId, title: title, type: "transcript", text: transcript)
        transcriptsByProjectId[projectId, default: []].append(
            TranscriptSegment(
                sourceId: source.sourceId,
                projectId: projectId,
                sessionId: nil,
                audioAssetId: nil,
                sourceType: "liveListening",
                title: title,
                analysis: transcript,
                segmentTimestampISO8601: source.createdAtISO8601,
                createdAtISO8601: source.createdAtISO8601,
                isFinal: true,
                speakerLabel: nil
            )
        )
        return source
    }

    func fetchProjectContext(projectId: String, token: String) async throws -> ProjectContextSummary {
        let snapshot = try await fetchProjectContextSnapshot(projectId: projectId, token: token)
        return ProjectContextSummary(
            summary: snapshot.mergedText.isEmpty ? "No saved context yet" : snapshot.mergedText,
            sources: snapshot.allSources,
            lastUpdatedISO8601: snapshot.lastUpdatedISO8601
        )
    }

    func fetchProjectContextSnapshot(projectId: String, token: String) async throws -> ProjectContextSnapshot {
        let projectName = projects.first(where: { $0.projectId == projectId })?.name ?? "Project"
        let docs = sourceItemsByProjectId[projectId]?.filter { $0.sourceType != "transcript" } ?? []
        let transcripts = sourceItemsByProjectId[projectId]?.filter { $0.sourceType == "transcript" } ?? []
        let chatHistory = chatTurnsByProjectId[projectId, default: []]
            .map { "\($0.role.capitalized): \($0.content)" }
            .joined(separator: "\n")
        let documentContext = documentsByProjectId[projectId, default: []]
            .map { "Document: \($0.fileName)\n\($0.extractedText)" }
            .joined(separator: "\n\n")
        let transcriptHistory = transcriptsByProjectId[projectId, default: []]
            .map { "Transcript: \($0.title)\n\($0.analysis)" }
            .joined(separator: "\n\n")
        let merged = [projectName, documentContext, transcriptHistory, chatHistory]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")

        return ProjectContextSnapshot(
            projectId: projectId,
            projectName: projectName,
            manualText: "",
            documentContext: documentContext,
            transcriptHistory: transcriptHistory,
            chatHistory: chatHistory,
            mergedText: merged,
            documents: docs,
            transcripts: transcripts,
            lastUpdatedISO8601: ISO8601DateFormatter().string(from: Date())
        )
    }

    func saveAudioAsset(projectId: String, title: String, mimeType: String, token: String) async throws -> ProjectAudioAsset {
        let asset = ProjectAudioAsset(
            assetId: UUID().uuidString,
            projectId: projectId,
            title: title,
            sourceType: "liveRecording",
            mimeType: mimeType,
            storedPath: nil,
            durationSeconds: nil,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date()),
            transcriptionStatus: "pending"
        )
        audioAssetsByProjectId[projectId, default: []].append(asset)
        return asset
    }

    func saveProjectSummary(projectId: String, style: String, content: String, token: String) async throws -> ProjectSummary {
        let summary = ProjectSummary(
            summaryId: UUID().uuidString,
            projectId: projectId,
            style: style,
            content: content,
            sourceSnapshotHash: nil,
            generatedAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
        summariesByProjectId[projectId, default: []].append(summary)
        return summary
    }

    func listProjectSummaries(projectId: String, token: String) async throws -> [ProjectSummary] {
        summariesByProjectId[projectId] ?? []
    }

    func listProjectDocuments(projectId: String, token: String) async throws -> [ProjectDocument] {
        documentsByProjectId[projectId] ?? []
    }

    func listProjectAudioAssets(projectId: String, token: String) async throws -> [ProjectAudioAsset] {
        audioAssetsByProjectId[projectId] ?? []
    }

    func listProjectTranscripts(projectId: String, token: String) async throws -> [TranscriptSegment] {
        transcriptsByProjectId[projectId] ?? []
    }

    func importAudioAsset(
        projectId: String,
        fileName: String,
        mimeType: String,
        localFileURL: URL?,
        durationSeconds: TimeInterval?,
        sourceType: String,
        transcript: String?,
        token: String
    ) async throws -> ProjectAudioAsset {
        let asset = ProjectAudioAsset(
            assetId: UUID().uuidString,
            projectId: projectId,
            title: fileName,
            sourceType: sourceType,
            mimeType: mimeType,
            storedPath: localFileURL?.path,
            durationSeconds: durationSeconds,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date()),
            transcriptionStatus: transcript?.isEmpty == false ? "completed" : "failed"
        )
        audioAssetsByProjectId[projectId, default: []].append(asset)
        if let transcript, !transcript.isEmpty {
            _ = try await saveTranscript(projectId: projectId, title: "Transcript – \(fileName)", transcript: transcript, token: token)
        }
        return asset
    }

    func saveChatTurn(projectId: String, role: String, content: String, token: String) async throws -> ChatTurn {
        let turn = ChatTurn(
            turnId: UUID().uuidString,
            projectId: projectId,
            role: role,
            content: content,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date()),
            turnIndex: chatTurnsByProjectId[projectId, default: []].count
        )
        chatTurnsByProjectId[projectId, default: []].append(turn)
        return turn
    }

    func listChatTurns(projectId: String, token: String) async throws -> [ChatTurn] {
        chatTurnsByProjectId[projectId] ?? []
    }

    func clearChatTurns(projectId: String, token: String) async throws {
        chatTurnsByProjectId[projectId] = []
    }

    func buildAIGenerationContext(projectId: String, userName: String?, token: String) async throws -> AIGenerationContext {
        let snapshot = try await fetchProjectContextSnapshot(projectId: projectId, token: token)
        let transcripts = transcriptsByProjectId[projectId, default: []].sorted { $0.createdAtISO8601 < $1.createdAtISO8601 }
        let latestTranscript = transcripts.last?.analysis ?? ""
        let olderTranscripts = transcripts.dropLast().map { "\($0.title)\n\($0.analysis)" }
        let notes = notesByProjectId[projectId] ?? ""
        let baseContext = [
            notes.isEmpty ? nil : "Project Background:\n\(notes)",
            snapshot.documentContext.isEmpty ? nil : snapshot.documentContext,
            snapshot.chatHistory.isEmpty ? nil : snapshot.chatHistory
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")

        return AIGenerationContext(
            projectId: projectId,
            projectName: snapshot.projectName,
            transcriptHistory: ([baseContext] + olderTranscripts).filter { !$0.isEmpty },
            liveTranscript: latestTranscript.isEmpty ? baseContext : latestTranscript,
            userName: userName
        )
    }

    func saveProjectNotes(projectId: String, text: String, token: String) async throws -> UserProject {
        notesByProjectId[projectId] = text
        return projects.first(where: { $0.projectId == projectId }) ?? UserProject(projectId: projectId, name: "Project", goal: nil, manualText: text, createdAtISO8601: "", updatedAtISO8601: "")
    }

    func loadProjectNotes(projectId: String, token: String) async throws -> String {
        notesByProjectId[projectId] ?? ""
    }

    func deleteProjectSource(projectId: String, sourceId: String, token: String) async throws {
        documentsByProjectId[projectId]?.removeAll { $0.sourceId == sourceId }
        transcriptsByProjectId[projectId]?.removeAll { $0.sourceId == sourceId }
        audioAssetsByProjectId[projectId]?.removeAll { $0.assetId == sourceId }
    }

    func deleteProject(projectId: String, token: String) async throws {
        projects.removeAll { $0.projectId == projectId }
        documentsByProjectId.removeValue(forKey: projectId)
        transcriptsByProjectId.removeValue(forKey: projectId)
        audioAssetsByProjectId.removeValue(forKey: projectId)
    }

    func storedSourceTexts(projectId: String) -> [String] {
        let documents = documentsByProjectId[projectId, default: []].map(\.extractedText)
        let transcripts = transcriptsByProjectId[projectId, default: []].map(\.analysis)
        return documents + transcripts
    }

    private func makeSource(projectId: String, title: String, type: String, text: String) -> SourceItem {
        let source = SourceItem(
            sourceId: UUID().uuidString,
            sourceType: type,
            title: title,
            analysis: text,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date())
        )
        sourceItemsByProjectId[projectId, default: []].append(source)
        return source
    }
}

private actor ProjectScopedLocalStore {
    private struct PersistedState: Codable {
        var documentsByProjectId: [String: [ProjectDocument]] = [:]
        var transcriptsByProjectId: [String: [TranscriptSegment]] = [:]
        var audioAssetsByProjectId: [String: [ProjectAudioAsset]] = [:]
        var summariesByProjectId: [String: [ProjectSummary]] = [:]
        var chatTurnsByProjectId: [String: [ChatTurn]] = [:]
        var notesByProjectId: [String: String] = [:]
    }

    private var state: PersistedState
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let fileURL: URL

    init() {
        let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = supportDir.appendingPathComponent("AIResponse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("project-scoped-store.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? decoder.decode(PersistedState.self, from: data) {
            state = decoded
        } else {
            state = PersistedState()
        }
    }

    func listDocuments(projectId: String) -> [ProjectDocument] {
        state.documentsByProjectId[projectId] ?? []
    }

    func listTranscripts(projectId: String) -> [TranscriptSegment] {
        state.transcriptsByProjectId[projectId] ?? []
    }

    func listAudioAssets(projectId: String) -> [ProjectAudioAsset] {
        state.audioAssetsByProjectId[projectId] ?? []
    }

    func listSummaries(projectId: String) -> [ProjectSummary] {
        state.summariesByProjectId[projectId] ?? []
    }

    func listChatTurns(projectId: String) -> [ChatTurn] {
        state.chatTurnsByProjectId[projectId] ?? []
    }

    func recordDocument(
        projectId: String,
        fileName: String,
        fileType: String,
        storedPath: String?,
        extractedText: String,
        source: SourceItem
    ) {
        let document = ProjectDocument(
            sourceId: source.sourceId,
            projectId: projectId,
            fileName: fileName,
            fileType: fileType,
            storedPath: storedPath,
            extractedText: extractedText,
            extractionStatus: "completed",
            createdAtISO8601: source.createdAtISO8601,
            updatedAtISO8601: source.createdAtISO8601
        )
        state.documentsByProjectId[projectId, default: []].append(document)
        persist()
    }

    func recordTranscript(
        projectId: String,
        title: String,
        transcript: String,
        source: SourceItem,
        sessionId: String?,
        audioAssetId: String?,
        sourceType: String,
        isFinal: Bool
    ) {
        let segment = TranscriptSegment(
            sourceId: source.sourceId,
            projectId: projectId,
            sessionId: sessionId,
            audioAssetId: audioAssetId,
            sourceType: sourceType,
            title: title,
            analysis: transcript,
            segmentTimestampISO8601: source.createdAtISO8601,
            createdAtISO8601: source.createdAtISO8601,
            isFinal: isFinal,
            speakerLabel: nil
        )
        state.transcriptsByProjectId[projectId, default: []].append(segment)
        persist()
    }

    func recordAudioAsset(_ asset: ProjectAudioAsset) {
        state.audioAssetsByProjectId[asset.projectId, default: []].append(asset)
        persist()
    }

    func recordSummary(_ summary: ProjectSummary) {
        state.summariesByProjectId[summary.projectId, default: []].append(summary)
        persist()
    }

    func appendChatTurn(projectId: String, role: String, content: String) -> ChatTurn {
        let turn = ChatTurn(
            turnId: UUID().uuidString,
            projectId: projectId,
            role: role,
            content: content,
            createdAtISO8601: ISO8601DateFormatter().string(from: Date()),
            turnIndex: state.chatTurnsByProjectId[projectId, default: []].count
        )
        state.chatTurnsByProjectId[projectId, default: []].append(turn)
        persist()
        return turn
    }

    func clearChatTurns(projectId: String) {
        state.chatTurnsByProjectId[projectId] = []
        persist()
    }

    func saveNotes(projectId: String, text: String) {
        state.notesByProjectId[projectId] = text
        persist()
    }

    func loadNotes(projectId: String) -> String {
        state.notesByProjectId[projectId] ?? ""
    }

    func mergeSnapshot(projectId: String, remote: ProjectContextSnapshot?) -> ProjectContextSnapshot {
        let localDocuments = state.documentsByProjectId[projectId] ?? []
        let localTranscripts = state.transcriptsByProjectId[projectId] ?? []
        let localChat = state.chatTurnsByProjectId[projectId] ?? []

        let remoteDocuments = remote?.documents ?? []
        let remoteTranscripts = remote?.transcripts ?? []

        let documentSources = remoteDocuments + localDocuments.map {
            SourceItem(
                sourceId: $0.sourceId,
                sourceType: "file",
                title: $0.fileName,
                analysis: $0.extractedText,
                createdAtISO8601: $0.createdAtISO8601
            )
        }
        let transcriptSources = remoteTranscripts + localTranscripts.map {
            SourceItem(
                sourceId: $0.sourceId,
                sourceType: "transcript",
                title: $0.title,
                analysis: $0.analysis,
                createdAtISO8601: $0.createdAtISO8601
            )
        }
        let documentContext: [String] = {
            var parts: [String] = []
            if let remoteContext = remote?.documentContext, !remoteContext.isEmpty {
                parts.append(remoteContext)
            }
            parts.append(contentsOf: localDocuments.map {
                "Document: \($0.fileName)\n\($0.extractedText)"
            })
            return parts
        }()
        let transcriptContext: [String] = {
            var parts: [String] = []
            if let remoteContext = remote?.transcriptHistory, !remoteContext.isEmpty {
                parts.append(remoteContext)
            }
            parts.append(contentsOf: localTranscripts.map {
                "Transcript: \($0.title)\n\($0.analysis)"
            })
            return parts
        }()
        let chatHistory = localChat
            .sorted { $0.turnIndex < $1.turnIndex }
            .map { "\($0.role.capitalized): \($0.content)" }
            .joined(separator: "\n")
        let projectName = remote?.projectName ?? "Project"
        let manualText = state.notesByProjectId[projectId] ?? remote?.manualText ?? ""
        let mergedText = [
            projectName,
            manualText,
            documentContext.joined(separator: "\n\n"),
            transcriptContext.joined(separator: "\n\n"),
            chatHistory
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n\n")

        return ProjectContextSnapshot(
            projectId: projectId,
            projectName: projectName,
            manualText: manualText,
            documentContext: documentContext.joined(separator: "\n\n"),
            transcriptHistory: transcriptContext.joined(separator: "\n\n"),
            chatHistory: chatHistory,
            mergedText: mergedText,
            documents: deduplicateSources(documentSources),
            transcripts: deduplicateSources(transcriptSources),
            lastUpdatedISO8601: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func deduplicateSources(_ sources: [SourceItem]) -> [SourceItem] {
        var seen = Set<String>()
        return sources.filter { seen.insert($0.sourceId).inserted }
    }

    private func persist() {
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
