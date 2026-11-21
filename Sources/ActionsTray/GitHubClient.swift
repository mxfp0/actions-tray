import Foundation

struct GitHubClient: Sendable {
    enum RunsResponse: Sendable {
        case notModified
        case updated([WorkflowRun], etag: String?)
    }

    enum APIError: LocalizedError {
        case unauthorized
        case notFound
        case forbidden
        case rateLimited(reset: Date?)
        case status(Int)

        var errorDescription: String? {
            switch self {
            case .unauthorized: "GitHub rejected the token."
            case .notFound: "Repository not found, or the token can't see it."
            case .forbidden: "The token lacks permission for this action."
            case .rateLimited(let reset):
                if let reset { "Rate limited until \(reset.formatted(date: .omitted, time: .shortened))." } else { "Rate limited." }
            case .status(let code): "GitHub returned HTTP \(code)."
            }
        }
    }

    let token: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    func runs(repo: String, etag: String?) async throws -> RunsResponse {
        var request = request("/repos/\(repo)/actions/runs?per_page=50")
        if let etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await send(request)
        if response.statusCode == 304 {
            return .notModified
        }
        try check(response)
        let page = try Self.decoder().decode(RunsPage.self, from: data)
        return .updated(page.workflowRuns, etag: response.value(forHTTPHeaderField: "ETag"))
    }

    func repositoryFullName(_ slug: String) async throws -> String {
        let (data, response) = try await send(request("/repos/\(slug)"))
        try check(response)
        return try Self.decoder().decode(Repository.self, from: data).fullName
    }

    func rerunFailedJobs(repo: String, runID: Int) async throws {
        let (_, response) = try await send(request("/repos/\(repo)/actions/runs/\(runID)/rerun-failed-jobs", method: "POST"))
        try check(response)
    }

    func cancel(repo: String, runID: Int) async throws {
        let (_, response) = try await send(request("/repos/\(repo)/actions/runs/\(runID)/cancel", method: "POST"))
        try check(response)
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com\(path)")!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        return (data, response as! HTTPURLResponse)
    }

    private func check(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 403, 429:
            guard response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || response.statusCode == 429 else {
                throw APIError.forbidden
            }
            let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset")
                .flatMap(TimeInterval.init)
                .map(Date.init(timeIntervalSince1970:))
            throw APIError.rateLimited(reset: reset)
        default: throw APIError.status(response.statusCode)
        }
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
