import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from server"
        case .server(let code): return "Server error: \(code)"
        case .decoding: return "Failed to decode server response"
        }
    }
}

struct APIClient {
    var baseURL: URL = AppConfig.baseURL

    func makeRequest(
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil,
        accept: String? = nil,
        contentType: String = "application/json"
    ) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        if let accept {
            request.setValue(accept, forHTTPHeaderField: "Accept")
        }

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    func request(
        path: String,
        method: String = "GET",
        token: String? = nil,
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> Data {
        let request = makeRequest(path: path, method: method, token: token, body: body, contentType: contentType)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode) }
        return data
    }

    func multipartBody(
        fieldName: String,
        fileName: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
