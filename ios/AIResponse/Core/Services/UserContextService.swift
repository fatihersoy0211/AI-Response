import Foundation

struct UserContextService {
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
