import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(Int, String?)   // code + optional server message
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Sunucudan geçersiz yanıt alındı"
        case .server(let code, let message):
            if let msg = message, !msg.isEmpty {
                return msg
            }
            return "Sunucu hatası: \(code)"
        case .decoding:
            return "Sunucu yanıtı çözümlenemedi"
        }
    }
}

// Shared URLSession configured with sensible timeouts
private let _session: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest  = 30   // seconds to connect / send
    cfg.timeoutIntervalForResource = 120  // seconds for the full response
    return URLSession(configuration: cfg)
}()

// Streaming session — longer resource timeout for SSE
private let _streamSession: URLSession = {
    let cfg = URLSessionConfiguration.default
    cfg.timeoutIntervalForRequest  = 30
    cfg.timeoutIntervalForResource = 180
    return URLSession(configuration: cfg)
}()

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
        let req = makeRequest(path: path, method: method, token: token, body: body, contentType: contentType)
        let (data, response) = try await _session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            // Try to extract the "detail" field FastAPI returns
            let serverMessage = parseDetail(from: data)
            throw APIError.server(http.statusCode, serverMessage)
        }
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

    // FastAPI wraps errors as {"detail": "..."}
    private func parseDetail(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = obj["detail"]
        else { return nil }

        if let str = detail as? String { return str }
        // FastAPI validation errors: detail is an array
        if let arr = detail as? [[String: Any]] {
            return arr.compactMap { $0["msg"] as? String }.joined(separator: "; ")
        }
        return nil
    }
}

// Expose stream session for AIBackendService
extension APIClient {
    var streamSession: URLSession { _streamSession }
}
