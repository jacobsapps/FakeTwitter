import Foundation

enum HTTPClientError: LocalizedError {
    case invalidResponse
    case statusCode(Int, String)
    case encoding(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .statusCode(let code, let body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "Request failed with HTTP \(code)."
            }
            return "Request failed with HTTP \(code): \(trimmed)"
        case .encoding(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .decoding(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

final class HTTPClient {
    let baseURL: URL
    let session: URLSession

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func url(path: String) -> URL {
        if path.hasPrefix("/") {
            return baseURL.appending(path: String(path.dropFirst()))
        }
        return baseURL.appending(path: path)
    }

    /// Decodes a JSON response for a GET endpoint.
    func getJSON<Response: Decodable>(path: String, headers: [String: String] = [:]) async throws -> Response {
        let (data, _) = try await perform(path: path, method: "GET", headers: headers, body: nil)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw HTTPClientError.decoding(error)
        }
    }

    /// Sends a JSON POST and validates that the response is successful (2xx).
    @discardableResult
    func postJSONWithoutResponse<Request: Encodable>(
        path: String,
        payload: Request,
        headers: [String: String] = [:]
    ) async throws -> HTTPURLResponse {
        let body: Data
        do {
            body = try encoder.encode(payload)
        } catch {
            throw HTTPClientError.encoding(error)
        }

        let (_, response) = try await perform(
            path: path,
            method: "POST",
            headers: headers,
            body: body,
            contentType: "application/json"
        )
        return response
    }

    /// Sends a JSON POST and returns raw body + response without enforcing success status.
    /// Useful for retry logic that needs to inspect `Retry-After` and status codes.
    func postJSONRaw<Request: Encodable>(
        path: String,
        payload: Request,
        headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        let body: Data
        do {
            body = try encoder.encode(payload)
        } catch {
            throw HTTPClientError.encoding(error)
        }

        return try await perform(
            path: path,
            method: "POST",
            headers: headers,
            body: body,
            contentType: "application/json",
            validateStatusCode: false
        )
    }

    /// Sends a JSON POST and decodes a JSON response body.
    func postJSON<Request: Encodable, Response: Decodable>(
        path: String,
        payload: Request,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let body: Data
        do {
            body = try encoder.encode(payload)
        } catch {
            throw HTTPClientError.encoding(error)
        }

        let (data, _) = try await perform(
            path: path,
            method: "POST",
            headers: headers,
            body: body,
            contentType: "application/json"
        )

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw HTTPClientError.decoding(error)
        }
    }

    /// Core request performer used by helpers above.
    func perform(
        path: String,
        method: String,
        headers: [String: String] = [:],
        body: Data?,
        contentType: String? = nil,
        validateStatusCode: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url(path: path))
        request.httpMethod = method
        request.httpBody = body

        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }

        for (header, value) in headers {
            request.setValue(value, forHTTPHeaderField: header)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HTTPClientError.invalidResponse
        }

        if validateStatusCode && !(200...299).contains(http.statusCode) {
            throw HTTPClientError.statusCode(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return (data, http)
    }
}
