import Foundation

private struct SSEEventPayload: Decodable {
    let delta: String?
    let done: Bool?
    let error: String?
}

struct AIBackendService {
    private let api = APIClient()

    func streamAnswer(
        projectId: String,
        transcript: String,
        token: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = try JSONEncoder().encode(AIQueryRequest(projectId: projectId, transcript: transcript))
                    let request = api.makeRequest(
                        path: "/ai/respond",
                        method: "POST",
                        token: token,
                        body: body,
                        accept: "text/event-stream"
                    )

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode) }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }

                        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !raw.isEmpty else { continue }

                        let rawData = Data(raw.utf8)
                        if let payload = try? JSONDecoder().decode(SSEEventPayload.self, from: rawData) {
                            if let error = payload.error {
                                throw NSError(domain: "AIBackendService", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
                            }
                            if payload.done == true {
                                break
                            }
                            if let delta = payload.delta, !delta.isEmpty {
                                continuation.yield(delta)
                            }
                        } else {
                            continuation.yield(String(raw))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
