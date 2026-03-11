import Foundation

private struct SSEEventPayload: Decodable {
    let delta: String?
    let done: Bool?
    let error: String?
}

struct AIBackendService: AIResponseServicing {
    private let api = APIClient()

    func streamAnswer(context: AIGenerationContext, token: String) -> AsyncThrowingStream<String, Error> {
        streamAnswer(
            projectId: context.projectId,
            transcript: context.currentTranscript,
            sessionTranscript: context.combinedTranscriptMemory.isEmpty ? nil : context.combinedTranscriptMemory,
            userName: context.userName,
            token: token
        )
    }

    func streamAnswer(
        projectId: String,
        transcript: String,
        sessionTranscript: String?,
        userName: String?,
        token: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let body = try JSONEncoder().encode(AIQueryRequest(
                        projectId: projectId,
                        transcript: transcript,
                        sessionTranscript: sessionTranscript,
                        userName: userName
                    ))
                    let request = api.makeRequest(
                        path: "/ai/respond",
                        method: "POST",
                        token: token,
                        body: body,
                        accept: "text/event-stream"
                    )

                    // Use the dedicated streaming session (longer timeout)
                    let (bytes, response) = try await api.streamSession.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }

                    // On non-200, collect the body and extract the error detail
                    guard (200..<300).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes { errorData.append(byte) }
                        let detail = parseDetail(from: errorData)
                        throw APIError.server(http.statusCode, detail)
                    }

                    for try await line in bytes.lines {
                        // SSE lines must start with "data:"
                        guard line.hasPrefix("data:") else { continue }

                        let raw = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard !raw.isEmpty else { continue }

                        // Ignore the raw "[DONE]" marker some proxies insert
                        if raw == "[DONE]" { break }

                        let rawData = Data(raw.utf8)
                        guard let payload = try? JSONDecoder().decode(SSEEventPayload.self, from: rawData) else {
                            // Cannot decode: skip silently — do NOT yield raw text
                            continue
                        }

                        if let errorMessage = payload.error, !errorMessage.isEmpty {
                            throw NSError(
                                domain: "AIBackendService",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: errorMessage]
                            )
                        }
                        if payload.done == true { break }
                        if let delta = payload.delta, !delta.isEmpty {
                            continuation.yield(delta)
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // FastAPI wraps errors as {"detail": "..."}
    private func parseDetail(from data: Data) -> String? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let detail = obj["detail"]
        else { return nil }
        if let str = detail as? String { return str }
        if let arr = detail as? [[String: Any]] {
            return arr.compactMap { $0["msg"] as? String }.joined(separator: "; ")
        }
        return nil
    }
}

final class MockAIService: AIResponseServicing {
    private let responseText: String
    private let failureMessage: String?
    private(set) var recordedContexts: [AIGenerationContext] = []

    init(responseText: String, failureMessage: String? = nil) {
        self.responseText = responseText
        self.failureMessage = failureMessage
    }

    convenience init(launchConfiguration: AppLaunchConfiguration) {
        self.init(
            responseText: launchConfiguration.aiResponse,
            failureMessage: launchConfiguration.aiFailureMessage
        )
    }

    func streamAnswer(context: AIGenerationContext, token: String) -> AsyncThrowingStream<String, Error> {
        recordedContexts.append(context)
        return AsyncThrowingStream { continuation in
            if let failureMessage {
                continuation.finish(throwing: TestFailure.forced(failureMessage))
                return
            }
            continuation.yield(responseText)
            continuation.finish()
        }
    }
}
